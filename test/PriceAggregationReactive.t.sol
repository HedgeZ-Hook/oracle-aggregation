// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {FullMath} from "../src/libraries/FullMath.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {Test} from "forge-std/Test.sol";

import {IReactive} from "@reactive/interfaces/IReactive.sol";

import {PriceAggregationReactive} from "../src/PriceAggregationReactive.sol";

contract PriceAggregationReactiveTest is Test {
    uint256 internal constant SOURCE_CHAIN_ID = 8453;
    address internal constant POOL_A = address(0x1111);
    address internal constant POOL_B = address(0x2222);

    PriceAggregationReactive internal reactive;

    function setUp() external {
        PriceAggregationReactive.PoolConfig[]
            memory poolConfigs = new PriceAggregationReactive.PoolConfig[](2);

        poolConfigs[0] = PriceAggregationReactive.PoolConfig({
            sourceChainId: SOURCE_CHAIN_ID,
            pool: POOL_A,
            token0Decimals: 18,
            token1Decimals: 6,
            useQuoteAsBase: false,
            weight: 90
        });

        poolConfigs[1] = PriceAggregationReactive.PoolConfig({
            sourceChainId: SOURCE_CHAIN_ID,
            pool: POOL_B,
            token0Decimals: 6,
            token1Decimals: 18,
            useQuoteAsBase: true,
            weight: 10
        });

        reactive = new PriceAggregationReactive(120, poolConfigs, 0, address(0), 0);
    }

    function testAggregateTracksTimeWithoutNewEvents() external {
        vm.warp(100);
        reactive.react(_swapLog(POOL_A, 100, 1));
        reactive.react(_swapLog(POOL_B, -80, 1));

        vm.warp(160);
        reactive.react(_swapLog(POOL_A, 200, 2));

        vm.warp(220);
        (uint256 priceAt220, bool ready220, uint256 active220) = reactive
            .getAggregatePriceE18();
        assertTrue(ready220);
        assertEq(active220, 2);

        uint256 expectedAt220 = ((_priceAtTick(150, 18, 6) * 90) +
            (_priceAtTick(80, 18, 6) * 10)) / 100;
        assertEq(priceAt220, expectedAt220);

        vm.warp(230);
        (uint256 priceAt230, bool ready230, uint256 active230) = reactive
            .getAggregatePriceE18();
        assertTrue(ready230);
        assertEq(active230, 2);
        assertGt(priceAt230, priceAt220);

        uint256 expectedAt230 = ((_priceAtTick(158, 18, 6) * 90) +
            (_priceAtTick(80, 18, 6) * 10)) / 100;
        assertEq(priceAt230, expectedAt230);
    }

    function testAggregateReturnsZeroWhenNoPoolsInitialized() external view {
        (uint256 priceE18, bool ready, uint256 activePools) = reactive
            .getAggregatePriceE18();

        assertFalse(ready);
        assertEq(activePools, 0);
        assertEq(priceE18, 0);
    }

    function testPoolDirectionNormalizationUsesQuoteAsBase() external {
        vm.warp(100);
        reactive.react(_swapLog(POOL_B, -120, 1));

        bytes32 poolKey = reactive.getPoolKeyAt(1);
        (int24 tick, bool ready) = reactive.getPoolTick(poolKey, 0);
        (uint256 priceE18, bool priceReady) = reactive.getPoolPriceE18(
            poolKey,
            0
        );

        assertTrue(ready);
        assertTrue(priceReady);
        assertEq(tick, 120);
        assertEq(priceE18, _priceAtTick(120, 18, 6));
    }

    function testAggregateIntervalZeroUsesLatestStandardizedTicks() external {
        vm.warp(100);
        reactive.react(_swapLog(POOL_A, 120, 1));
        reactive.react(_swapLog(POOL_B, -90, 1));

        (uint256 priceE18, bool ready, uint256 activePools) = reactive
            .getAggregatePriceE18(0);

        assertTrue(ready);
        assertEq(activePools, 2);
        assertEq(
            priceE18,
            ((_priceAtTick(120, 18, 6) * 90) +
                (_priceAtTick(90, 18, 6) * 10)) / 100
        );
    }

    function testAggregateUsesConfiguredWeightsInsteadOfSimpleMean() external {
        vm.warp(100);
        reactive.react(_swapLog(POOL_A, 300, 1));
        reactive.react(_swapLog(POOL_B, -30, 1));

        (uint256 priceE18, bool ready, uint256 activePools) = reactive
            .getAggregatePriceE18(0);

        uint256 priceA = _priceAtTick(300, 18, 6);
        uint256 priceB = _priceAtTick(30, 18, 6);
        uint256 weightedAverage = ((priceA * 90) + (priceB * 10)) / 100;
        uint256 simpleMean = (priceA + priceB) / 2;

        assertTrue(ready);
        assertEq(activePools, 2);
        assertEq(priceE18, weightedAverage);
        assertTrue(priceE18 > simpleMean);
    }

    function testAggregateWithSingleActivePoolReturnsThatPoolAndNotReady() external {
        vm.warp(100);
        reactive.react(_swapLog(POOL_A, 75, 1));

        vm.warp(220);
        (uint256 priceE18, bool ready, uint256 activePools) = reactive
            .getAggregatePriceE18();

        assertFalse(ready);
        assertEq(activePools, 1);
        assertEq(priceE18, _priceAtTick(75, 18, 6));
    }

    function testAggregateWithOnlyPoolBActiveReturnsPoolBAndNotReady() external {
        vm.warp(100);
        reactive.react(_swapLog(POOL_B, -90, 1));

        vm.warp(220);
        (uint256 priceE18, bool ready, uint256 activePools) = reactive
            .getAggregatePriceE18();

        assertFalse(ready);
        assertEq(activePools, 1);
        assertEq(priceE18, _priceAtTick(90, 18, 6));
    }

    function testPoolTickAndPriceFallBackToLatestWhenNotReady() external {
        vm.warp(100);
        reactive.react(_swapLog(POOL_A, 140, 1));

        bytes32 poolKey = reactive.getPoolKeyAt(0);
        (int24 tick, bool tickReady) = reactive.getPoolTick(poolKey);
        (uint256 priceE18, bool priceReady) = reactive.getPoolPriceE18(poolKey);

        assertFalse(tickReady);
        assertFalse(priceReady);
        assertEq(tick, 140);
        assertEq(priceE18, _priceAtTick(140, 18, 6));
    }

    function testAggregateBeforeEnoughHistoryFallsBackToLatestTicks() external {
        vm.warp(100);
        reactive.react(_swapLog(POOL_A, 100, 1));
        reactive.react(_swapLog(POOL_B, -60, 1));

        vm.warp(160);
        reactive.react(_swapLog(POOL_A, 180, 2));
        reactive.react(_swapLog(POOL_B, -120, 2));

        (uint256 priceE18, bool ready, uint256 activePools) = reactive
            .getAggregatePriceE18();

        assertFalse(ready);
        assertEq(activePools, 2);
        assertEq(
            priceE18,
            ((_priceAtTick(180, 18, 6) * 90) +
                (_priceAtTick(120, 18, 6) * 10)) / 100
        );
    }

    function testAggregateHandlesNegativeAverageTicks() external {
        vm.warp(100);
        reactive.react(_swapLog(POOL_A, -200, 1));
        reactive.react(_swapLog(POOL_B, 160, 1));

        vm.warp(160);
        reactive.react(_swapLog(POOL_A, -100, 2));
        reactive.react(_swapLog(POOL_B, 40, 2));

        vm.warp(220);
        (uint256 priceE18, bool ready, uint256 activePools) = reactive
            .getAggregatePriceE18();

        assertTrue(ready);
        assertEq(activePools, 2);
        assertEq(
            priceE18,
            ((_priceAtTick(-150, 18, 6) * 90) +
                (_priceAtTick(-100, 18, 6) * 10)) / 100
        );
    }

    function _swapLog(
        address pool,
        int24 tick,
        uint256 blockNumber
    ) internal view returns (IReactive.LogRecord memory log) {
        log.chain_id = SOURCE_CHAIN_ID;
        log._contract = pool;
        log.topic_0 = uint256(reactive.V3_SWAP_TOPIC());
        log.topic_1 = uint256(uint160(address(0xAAAA)));
        log.topic_2 = uint256(uint160(address(0xBBBB)));
        log.data = abi.encode(
            int256(1e18),
            int256(-1e18),
            TickMath.getSqrtPriceAtTick(tick),
            uint128(1e18),
            tick
        );
        log.block_number = blockNumber;
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
