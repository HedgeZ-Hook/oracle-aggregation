// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AbstractPausableReactive} from "@reactive/abstract-base/AbstractPausableReactive.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/interfaces/ISystemContract.sol";

import {CachedTickTwap} from "./twap/CachedTickTwap.sol";

contract UniswapV3TickTwap is
    IReactive,
    AbstractPausableReactive,
    CachedTickTwap
{
    bytes32 public constant SWAP_TOPIC =
        keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");

    uint256 public immutable sourceChainId;
    address public immutable pool;
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
        uint256 indexed sourceBlockNumber,
        uint256 observedAt
    );
    event TickTwapUpdated(int24 indexed averageTick, uint256 observedAt);

    constructor(
        uint256 _sourceChainId,
        address _pool,
        uint80 _interval,
        uint8 _baseDecimals,
        uint8 _quoteDecimals,
        bool _useQuoteAsBase
    ) payable CachedTickTwap(_interval) {
        require(_pool != address(0), "zero pool");

        sourceChainId = _sourceChainId;
        pool = _pool;
        baseDecimals = _baseDecimals;
        quoteDecimals = _quoteDecimals;
        useQuoteAsBase = _useQuoteAsBase;

        if (!vm) {
            service.subscribe(
                sourceChainId,
                pool,
                uint256(SWAP_TOPIC),
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function react(LogRecord calldata log) external vmOnly {
        require(log.chain_id == sourceChainId, "bad chain");
        require(log._contract == pool, "bad pool");
        require(log.topic_0 == uint256(SWAP_TOPIC), "bad topic");
        (, , uint160 sqrtPriceX96, uint128 liquidity, int24 tick) = abi.decode(
            log.data,
            (int256, int256, uint160, uint128, int24)
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
            log.block_number,
            observedAt
        );
        emit TickTwapUpdated(averageTick, observedAt);
    }

    function getTick() external view returns (int24 tick, bool ready) {
        (tick, ready) = _resolvedRawTick();
        if (useQuoteAsBase) {
            tick = _inverseTick(tick);
        }
    }

    function getPriceE18()
        external
        view
        returns (uint256 priceE18, bool ready)
    {
        (int24 tick, bool hasTwap) = _resolvedRawTick();
        if (useQuoteAsBase) {
            tick = _inverseTick(tick);
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
            _contract: pool,
            topic_0: uint256(SWAP_TOPIC),
            topic_1: REACTIVE_IGNORE,
            topic_2: REACTIVE_IGNORE,
            topic_3: REACTIVE_IGNORE
        });
    }
}
