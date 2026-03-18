// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {AbstractPausableReactive} from "@reactive/abstract-base/AbstractPausableReactive.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {TickCumulativeOracleLib} from "./twap/TickCumulativeOracleLib.sol";

import {BlockContext} from "./libraries/BlockContext.sol";

contract PriceAggregationReactive is
    IReactive,
    AbstractPausableReactive,
    BlockContext
{
    uint64 public constant DEFAULT_CALLBACK_GAS_LIMIT = 1_000_000;

    bytes32 public constant V3_SWAP_TOPIC =
        keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");

    struct PoolConfig {
        uint256 sourceChainId;
        address pool;
        uint8 token0Decimals;
        uint8 token1Decimals;
        bool useQuoteAsBase;
        uint256 weight;
    }

    struct PoolState {
        int24 latestTick;
        uint256 latestTickTimestamp;
        bool initialized;
    }

    uint80 public immutable defaultInterval;
    uint256 public immutable callbackChainId;
    address public immutable callbackTarget;
    uint64 public immutable callbackGasLimit;

    uint256 public lastNotifiedAggregatePriceE18;
    bool public hasNotifiedAggregatePrice;

    using TickCumulativeOracleLib for TickCumulativeOracleLib.State;

    PoolConfig[] internal _poolConfigs;
    mapping(bytes32 => uint256) internal _poolIndexPlusOne;
    mapping(bytes32 => PoolState) public poolStates;
    mapping(bytes32 => TickCumulativeOracleLib.State) internal _oracles;
    mapping(bytes32 => TickCumulativeOracleLib.Cursor)
        internal _defaultIntervalCursors;

    event PoolObserved(
        bytes32 indexed poolKey,
        int24 indexed standardizedTick,
        uint256 indexed sourceBlockNumber,
        uint256 observedAt
    );
    event AggregateComputed(
        uint256 aggregatePriceE18,
        bool ready,
        uint256 activePools,
        uint256 observedAt
    );

    constructor(
        uint80 _defaultInterval,
        PoolConfig[] memory poolConfigs_,
        uint256 _callbackChainId,
        address _callbackTarget,
        uint64 _callbackGasLimit
    ) payable {
        require(poolConfigs_.length > 0, "no pools");
        defaultInterval = _defaultInterval;
        for (uint256 i = 0; i < poolConfigs_.length; ++i) {
            PoolConfig memory cfg = poolConfigs_[i];
            _validatePoolConfig(cfg);

            bytes32 poolKey = _poolKey(cfg);
            require(_poolIndexPlusOne[poolKey] == 0, "duplicate pool");

            _poolConfigs.push(cfg);
            _poolIndexPlusOne[poolKey] = _poolConfigs.length;

            if (!vm) {
                _subscribe(cfg);
            }
        }

        callbackChainId = _callbackChainId;
        callbackTarget = _callbackTarget;
        callbackGasLimit = _callbackGasLimit == 0
            ? DEFAULT_CALLBACK_GAS_LIMIT
            : _callbackGasLimit;
    }

    function poolCount() external view returns (uint256) {
        return _poolConfigs.length;
    }

    function getPoolConfig(
        uint256 index
    ) external view returns (PoolConfig memory) {
        return _poolConfigs[index];
    }

    function getPoolKeyAt(uint256 index) external view returns (bytes32) {
        return _poolKey(_poolConfigs[index]);
    }

    function getPoolTick(
        bytes32 poolKey
    ) external view returns (int24 tick, bool ready) {
        return _resolvedPoolTick(poolKey, defaultInterval);
    }

    function getPoolTick(
        bytes32 poolKey,
        uint256 interval
    ) external view returns (int24 tick, bool ready) {
        return _resolvedPoolTick(poolKey, interval);
    }

    function getPoolPriceE18(
        bytes32 poolKey
    ) external view returns (uint256 priceE18, bool ready) {
        return _poolPrice(poolKey, defaultInterval);
    }

    function getPoolPriceE18(
        bytes32 poolKey,
        uint256 interval
    ) external view returns (uint256 priceE18, bool ready) {
        return _poolPrice(poolKey, interval);
    }

    function getAggregatePriceE18()
        external
        view
        returns (uint256 priceE18, bool ready, uint256 activePools)
    {
        return _aggregate(defaultInterval);
    }

    function getAggregatePriceE18(
        uint256 interval
    )
        external
        view
        returns (uint256 priceE18, bool ready, uint256 activePools)
    {
        return _aggregate(interval);
    }

    function react(LogRecord calldata log) external vmOnly {
        bytes32 poolKey = _poolKeyFromLog(log);
        uint256 poolIndexPlusOne = _poolIndexPlusOne[poolKey];
        require(poolIndexPlusOne != 0, "unknown pool");

        PoolConfig memory cfg = _poolConfigs[poolIndexPlusOne - 1];
        int24 standardizedTick = _standardizedTick(cfg, log.data);
        uint256 observedAt = _blockTimestamp();

        PoolState storage state = poolStates[poolKey];
        state.latestTick = standardizedTick;
        state.latestTickTimestamp = observedAt;
        state.initialized = true;

        _oracles[poolKey].update(standardizedTick, observedAt);
        (
            uint256 aggregatePriceE18,
            bool ready,
            uint256 activePools
        ) = _aggregateWithDefaultIntervalCursor();

        emit PoolObserved(
            poolKey,
            standardizedTick,
            log.block_number,
            observedAt
        );
        emit AggregateComputed(
            aggregatePriceE18,
            ready,
            activePools,
            observedAt
        );

        if (
            callbackTarget != address(0) &&
            activePools > 0 &&
            (!hasNotifiedAggregatePrice ||
                aggregatePriceE18 != lastNotifiedAggregatePriceE18)
        ) {
            hasNotifiedAggregatePrice = true;
            lastNotifiedAggregatePriceE18 = aggregatePriceE18;

            bytes memory payload = abi.encodeWithSignature(
                "onAggregatedPrice(address,address,uint256,uint256)",
                address(0),
                address(this),
                aggregatePriceE18,
                activePools
            );
            emit Callback(
                callbackChainId,
                callbackTarget,
                callbackGasLimit,
                payload
            );
        }
    }

    function getPausableSubscriptions()
        internal
        view
        override
        returns (Subscription[] memory subscriptions)
    {
        subscriptions = new Subscription[](_poolConfigs.length);

        for (uint256 i = 0; i < _poolConfigs.length; ++i) {
            PoolConfig memory cfg = _poolConfigs[i];
            subscriptions[i] = Subscription({
                chain_id: cfg.sourceChainId,
                _contract: cfg.pool,
                topic_0: uint256(V3_SWAP_TOPIC),
                topic_1: REACTIVE_IGNORE,
                topic_2: REACTIVE_IGNORE,
                topic_3: REACTIVE_IGNORE
            });
        }
    }

    function _validatePoolConfig(PoolConfig memory cfg) internal pure {
        require(cfg.pool != address(0), "zero pool");
        require(cfg.weight > 0, "zero weight");
    }

    function _subscribe(PoolConfig memory cfg) internal {
        service.subscribe(
            cfg.sourceChainId,
            cfg.pool,
            uint256(V3_SWAP_TOPIC),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    function _poolPrice(
        bytes32 poolKey,
        uint256 interval
    ) internal view returns (uint256 priceE18, bool ready) {
        PoolConfig memory cfg = _poolConfigByKey(poolKey);
        (int24 tick, bool hasTwap) = _resolvedPoolTick(poolKey, interval);
        return (
            _priceAtTick(
                tick,
                _effectiveBaseDecimals(cfg),
                _effectiveQuoteDecimals(cfg)
            ),
            hasTwap
        );
    }

    function _aggregate(
        uint256 interval
    )
        internal
        view
        returns (uint256 aggregatePriceE18, bool ready, uint256 activePools)
    {
        uint256 weightedPriceSum;
        uint256 totalWeight;
        bool allReady = true;

        for (uint256 i = 0; i < _poolConfigs.length; ++i) {
            PoolConfig memory cfg = _poolConfigs[i];
            bytes32 poolKey = _poolKey(cfg);
            PoolState memory state = poolStates[poolKey];
            if (!state.initialized) {
                allReady = false;
                continue;
            }

            (uint256 poolPriceE18, bool poolReady) = _poolPrice(
                poolKey,
                interval
            );
            weightedPriceSum += poolPriceE18 * cfg.weight;
            totalWeight += cfg.weight;
            activePools++;
            if (!poolReady) {
                allReady = false;
            }
        }

        if (activePools == 0 || totalWeight == 0) {
            return (0, false, 0);
        }

        return (
            weightedPriceSum / totalWeight,
            allReady && activePools == _poolConfigs.length,
            activePools
        );
    }

    function _aggregateWithDefaultIntervalCursor()
        internal
        returns (uint256 aggregatePriceE18, bool ready, uint256 activePools)
    {
        uint256 weightedPriceSum;
        uint256 totalWeight;
        bool allReady = true;

        for (uint256 i = 0; i < _poolConfigs.length; ++i) {
            PoolConfig memory cfg = _poolConfigs[i];
            bytes32 poolKey = _poolKey(cfg);
            PoolState memory state = poolStates[poolKey];
            if (!state.initialized) {
                allReady = false;
                continue;
            }

            (
                uint256 poolPriceE18,
                bool poolReady
            ) = _poolPriceWithDefaultIntervalCursor(poolKey);
            weightedPriceSum += poolPriceE18 * cfg.weight;
            totalWeight += cfg.weight;
            activePools++;
            if (!poolReady) {
                allReady = false;
            }
        }

        if (activePools == 0 || totalWeight == 0) {
            return (0, false, 0);
        }

        return (
            weightedPriceSum / totalWeight,
            allReady && activePools == _poolConfigs.length,
            activePools
        );
    }

    function _resolvedPoolTick(
        bytes32 poolKey,
        uint256 interval
    ) internal view returns (int24 averageTick, bool ready) {
        PoolState memory state = poolStates[poolKey];
        if (!state.initialized) {
            return (0, false);
        }

        if (interval == 0) {
            return (state.latestTick, true);
        }

        (averageTick, ready) = _oracles[poolKey].calculateAverageTick(
            interval,
            state.latestTick,
            state.latestTickTimestamp,
            _blockTimestamp()
        );
        if (!ready) {
            return (state.latestTick, false);
        }
    }

    function _poolPriceWithDefaultIntervalCursor(
        bytes32 poolKey
    ) internal returns (uint256 priceE18, bool ready) {
        PoolConfig memory cfg = _poolConfigByKey(poolKey);
        (int24 tick, bool hasTwap) = _resolvedPoolTickWithDefaultIntervalCursor(
            poolKey
        );
        return (
            _priceAtTick(
                tick,
                _effectiveBaseDecimals(cfg),
                _effectiveQuoteDecimals(cfg)
            ),
            hasTwap
        );
    }

    function _resolvedPoolTickWithDefaultIntervalCursor(
        bytes32 poolKey
    ) internal returns (int24 averageTick, bool ready) {
        PoolState memory state = poolStates[poolKey];
        if (!state.initialized) {
            return (0, false);
        }

        if (defaultInterval == 0) {
            return (state.latestTick, true);
        }

        (averageTick, ready) = _oracles[poolKey].calculateAverageTickWithCursor(
            _defaultIntervalCursors[poolKey],
            defaultInterval,
            state.latestTick,
            state.latestTickTimestamp,
            _blockTimestamp()
        );
        if (!ready) {
            return (state.latestTick, false);
        }
    }

    function _poolConfigByKey(
        bytes32 poolKey
    ) internal view returns (PoolConfig memory) {
        uint256 poolIndexPlusOne = _poolIndexPlusOne[poolKey];
        require(poolIndexPlusOne != 0, "unknown pool");
        return _poolConfigs[poolIndexPlusOne - 1];
    }

    function _standardizedTick(
        PoolConfig memory cfg,
        bytes calldata data
    ) internal pure returns (int24) {
        int24 rawTick;
        (, , , , rawTick) = abi.decode(
            data,
            (int256, int256, uint160, uint128, int24)
        );
        return cfg.useQuoteAsBase ? -rawTick : rawTick;
    }

    function _poolKey(PoolConfig memory cfg) internal pure returns (bytes32) {
        return keccak256(abi.encode(cfg.sourceChainId, cfg.pool));
    }

    function _poolKeyFromLog(
        LogRecord calldata log
    ) internal pure returns (bytes32) {
        if (log.topic_0 != uint256(V3_SWAP_TOPIC)) {
            revert("bad topic");
        }
        return keccak256(abi.encode(log.chain_id, log._contract));
    }

    function _effectiveBaseDecimals(
        PoolConfig memory cfg
    ) internal pure returns (uint8) {
        return cfg.useQuoteAsBase ? cfg.token1Decimals : cfg.token0Decimals;
    }

    function _effectiveQuoteDecimals(
        PoolConfig memory cfg
    ) internal pure returns (uint8) {
        return cfg.useQuoteAsBase ? cfg.token0Decimals : cfg.token1Decimals;
    }

    function _priceAtTick(
        int24 tick,
        uint8 baseDecimals,
        uint8 quoteDecimals
    ) internal pure returns (uint256) {
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        uint256 ratioX128 = FullMath.mulDiv(
            uint256(sqrtPriceX96),
            uint256(sqrtPriceX96),
            uint256(1) << 64
        );

        return
            FullMath.mulDiv(
                ratioX128,
                (10 ** baseDecimals) * 1e18,
                (uint256(1) << 128) * (10 ** quoteDecimals)
            );
    }
}
