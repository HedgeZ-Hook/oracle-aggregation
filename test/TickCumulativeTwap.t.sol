// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {FullMath} from "v4-core/libraries/FullMath.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Test} from "forge-std/Test.sol";

import {TickCumulativeTwap} from "../src/twap/TickCumulativeTwap.sol";

contract TickCumulativeTwapHarness is TickCumulativeTwap {
    function updateTick(int24 tick, uint256 timestamp) external returns (bool) {
        return _updateTick(tick, timestamp);
    }

    function calculateAverageTick(uint256 interval, int24 tick, uint256 latestUpdatedTimestamp)
        external
        view
        returns (int24 averageTick, bool hasTwap)
    {
        return _calculateAverageTick(interval, tick, latestUpdatedTimestamp);
    }

    function calculatePriceTwap(
        uint256 interval,
        int24 tick,
        uint256 latestUpdatedTimestamp,
        uint8 baseDecimals,
        uint8 quoteDecimals
    ) external view returns (uint256 priceE18, bool hasTwap) {
        return _calculatePriceTwap(interval, tick, latestUpdatedTimestamp, baseDecimals, quoteDecimals);
    }

    function priceAtTick(int24 tick, uint8 baseDecimals, uint8 quoteDecimals) external pure returns (uint256) {
        return _priceAtTick(tick, baseDecimals, quoteDecimals);
    }
}

contract TickCumulativeTwapTest is Test {
    TickCumulativeTwapHarness internal twap;

    function setUp() external {
        twap = new TickCumulativeTwapHarness();
    }

    function testCalculatesAverageTick() external {
        vm.warp(100);
        twap.updateTick(100, block.timestamp);

        vm.warp(160);
        twap.updateTick(200, block.timestamp);

        vm.warp(220);
        (int24 averageTick, bool hasTwap) = twap.calculateAverageTick(120, 200, 160);

        assertTrue(hasTwap);
        assertEq(averageTick, 150);
    }

    function testRoundsNegativeAverageTickTowardNegativeInfinity() external {
        vm.warp(100);
        twap.updateTick(-100, block.timestamp);

        vm.warp(160);
        twap.updateTick(0, block.timestamp);

        vm.warp(220);
        (int24 averageTick, bool hasTwap) = twap.calculateAverageTick(90, 0, 160);

        assertTrue(hasTwap);
        assertEq(averageTick, -34);
    }

    function testConvertsAverageTickToPrice() external {
        vm.warp(100);
        twap.updateTick(0, block.timestamp);

        vm.warp(160);
        twap.updateTick(100, block.timestamp);

        vm.warp(220);
        (uint256 priceE18, bool hasTwap) = twap.calculatePriceTwap(120, 100, 160, 18, 18);

        assertTrue(hasTwap);
        assertEq(priceE18, twap.priceAtTick(50, 18, 18));
    }

    function testFuzzPriceAtTickDoesNotRevert(int24 tick, uint8 baseDecimals, uint8 quoteDecimals) external view {
        baseDecimals = uint8(bound(baseDecimals, 0, 18));
        quoteDecimals = uint8(bound(quoteDecimals, 0, 18));
        tick = int24(bound(tick, TickMath.MIN_TICK, TickMath.MAX_TICK));

        twap.priceAtTick(tick, baseDecimals, quoteDecimals);
    }

    function testFuzzPriceAtTickIsMonotonic(
        int24 tickA,
        int24 tickB,
        uint8 baseDecimals,
        uint8 quoteDecimals
    ) external view {
        baseDecimals = uint8(bound(baseDecimals, 0, 18));
        quoteDecimals = uint8(bound(quoteDecimals, 0, 18));
        tickA = int24(bound(tickA, TickMath.MIN_TICK, TickMath.MAX_TICK));
        tickB = int24(bound(tickB, TickMath.MIN_TICK, TickMath.MAX_TICK));

        if (tickA > tickB) {
            (tickA, tickB) = (tickB, tickA);
        }

        uint256 priceA = twap.priceAtTick(tickA, baseDecimals, quoteDecimals);
        uint256 priceB = twap.priceAtTick(tickB, baseDecimals, quoteDecimals);

        assertLe(priceA, priceB);
    }

    function testFuzzPriceAtTickMatchesReferenceOnSafeSquare(
        int24 tick,
        uint8 baseDecimals,
        uint8 quoteDecimals
    ) external view {
        baseDecimals = uint8(bound(baseDecimals, 0, 18));
        quoteDecimals = uint8(bound(quoteDecimals, 0, 18));
        tick = int24(bound(tick, TickMath.MIN_TICK, TickMath.MAX_TICK));

        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(tick);
        vm.assume(uint256(sqrtPriceX96) <= type(uint128).max);

        uint256 actual = twap.priceAtTick(tick, baseDecimals, quoteDecimals);
        uint256 expectedPrice = FullMath.mulDiv(
            uint256(sqrtPriceX96) * uint256(sqrtPriceX96),
            (10 ** baseDecimals) * 1e18,
            (uint256(1) << 192) * (10 ** quoteDecimals)
        );

        assertEq(actual, expectedPrice);
    }
}
