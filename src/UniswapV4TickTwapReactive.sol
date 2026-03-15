// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {AbstractPausableReactive} from "@reactive/abstract-base/AbstractPausableReactive.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";

import {CachedTickTwap} from "./twap/CachedTickTwap.sol";

contract UniswapV4TickTwapReactive is
    IReactive,
    AbstractPausableReactive,
    CachedTickTwap
{
    bytes32 public constant SWAP_TOPIC =
        keccak256(
            "Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)"
        );

    uint256 public immutable sourceChainId;
    address public immutable poolManager;
    bytes32 public immutable poolId;
    uint8 public immutable baseDecimals;
    uint8 public immutable quoteDecimals;
    bool public immutable useQuoteAsBase;

    int24 public latestTick;
    uint256 public latestTickTimestamp;
    bool public initialized;

    event SwapObserved(
        int24 indexed tick,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint24 fee,
        uint256 indexed sourceBlockNumber,
        uint256 observedAt
    );
    event TickTwapUpdated(int24 indexed averageTick, uint256 observedAt);

    constructor(
        uint256 sourceChainId_,
        address poolManager_,
        bytes32 poolId_,
        uint80 interval_,
        uint8 baseDecimals_,
        uint8 quoteDecimals_,
        bool useQuoteAsBase_
    ) CachedTickTwap(interval_) {
        require(poolManager_ != address(0), "zero manager");

        sourceChainId = sourceChainId_;
        poolManager = poolManager_;
        poolId = poolId_;
        baseDecimals = baseDecimals_;
        quoteDecimals = quoteDecimals_;
        useQuoteAsBase = useQuoteAsBase_;

        if (!vm) {
            service.subscribe(
                sourceChainId,
                poolManager,
                uint256(SWAP_TOPIC),
                uint256(poolId),
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function react(LogRecord calldata log) external vmOnly {
        require(log.chain_id == sourceChainId, "bad chain");
        require(log._contract == poolManager, "bad manager");
        require(log.topic_0 == uint256(SWAP_TOPIC), "bad topic");
        require(log.topic_1 == uint256(poolId), "bad pool");

        (
            ,
            ,
            uint160 sqrtPriceX96,
            uint128 liquidity,
            int24 tick,
            uint24 fee
        ) = abi.decode(
                log.data,
                (int128, int128, uint160, uint128, int24, uint24)
            );

        uint256 observedAt = _blockTimestamp();
        latestTick = tick;
        latestTickTimestamp = observedAt;
        initialized = true;

        int24 averageTick = _cacheAverageTick(_interval, tick, observedAt);

        emit SwapObserved(
            tick,
            sqrtPriceX96,
            liquidity,
            fee,
            log.block_number,
            observedAt
        );
        emit TickTwapUpdated(averageTick, observedAt);
    }

    function getTick() external view returns (int24 tick, bool ready) {
        (tick, ready) = _resolvedRawTick();
        if (useQuoteAsBase) {
            tick = -tick;
        }
    }

    function getPriceE18()
        external
        view
        returns (uint256 priceE18, bool ready)
    {
        (int24 tick, bool hasTwap) = _resolvedRawTick();
        if (useQuoteAsBase) {
            tick = -tick;
        }

        return (_priceAtTick(tick, baseDecimals, quoteDecimals), hasTwap);
    }

    function _resolvedRawTick()
        internal
        view
        returns (int24 averageTick, bool ready)
    {
        if (!initialized) {
            return (0, false);
        }

        if (_interval == 0) {
            return (latestTick, true);
        }

        (averageTick, ready) = _calculateAverageTick(
            _interval,
            latestTick,
            latestTickTimestamp
        );
        if (!ready) {
            return (latestTick, false);
        }
    }

    function getPausableSubscriptions()
        internal
        view
        override
        returns (Subscription[] memory subscriptions)
    {
        subscriptions = new Subscription[](1);
        subscriptions[0] = Subscription({
            chain_id: sourceChainId,
            _contract: poolManager,
            topic_0: uint256(SWAP_TOPIC),
            topic_1: uint256(poolId),
            topic_2: REACTIVE_IGNORE,
            topic_3: REACTIVE_IGNORE
        });
    }
}
