// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {FullMath} from "v4-core/libraries/FullMath.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Test} from "forge-std/Test.sol";

import {IReactive} from "@reactive/interfaces/IReactive.sol";

import {UniswapV4TickTwapReactive} from "../src/UniswapV4TickTwapReactive.sol";

contract UniswapV4TickTwapReactiveTest is Test {
    uint256 internal constant SOURCE_CHAIN_ID = 130;
    address internal constant POOL_MANAGER = address(0x5678);
    bytes32 internal constant POOL_ID = keccak256("ETH/USDC:500");

    UniswapV4TickTwapReactive internal reactive;
    UniswapV4TickTwapReactive internal inverseReactive;

    function setUp() external {
        reactive = new UniswapV4TickTwapReactive(
            SOURCE_CHAIN_ID,
            POOL_MANAGER,
            POOL_ID,
            120,
            18,
            18,
            false
        );
        inverseReactive = new UniswapV4TickTwapReactive(
            SOURCE_CHAIN_ID,
            POOL_MANAGER,
            POOL_ID,
            120,
            18,
            18,
            true
        );
    }

    function testReactUpdatesLatestTickAndFallsBackBeforeEnoughHistory()
        external
    {
        vm.warp(100);
        reactive.react(
            _swapLog(100, 79228162514264337593543950336, 1e18, 500, 1)
        );

        vm.warp(160);
        reactive.react(
            _swapLog(200, 79625275426524748796330556128, 1e18, 500, 2)
        );

        (int24 averageTick, bool tickReady) = reactive.getTick();
        (uint256 priceE18, bool priceReady) = reactive.getPriceE18();

        assertFalse(tickReady);
        assertFalse(priceReady);
        assertEq(averageTick, 200);
        assertGt(priceE18, 0);
        assertEq(reactive.latestTick(), 200);
        assertEq(reactive.latestTickTimestamp(), 160);
    }

    function testReactComputesReadyTwapAfterEnoughTime() external {
        vm.warp(100);
        reactive.react(
            _swapLog(100, 79228162514264337593543950336, 1e18, 500, 1)
        );

        vm.warp(160);
        reactive.react(
            _swapLog(200, 79625275426524748796330556128, 1e18, 500, 2)
        );

        vm.warp(220);
        (int24 averageTick, bool tickReady) = reactive.getTick();
        (uint256 priceE18, bool priceReady) = reactive.getPriceE18();

        assertTrue(tickReady);
        assertTrue(priceReady);
        assertEq(averageTick, 150);
        assertEq(priceE18, _priceAtTick(150, 18, 18));
    }

    function testUseQuoteAsBaseInvertsTickAndPrice() external {
        vm.warp(100);
        reactive.react(
            _swapLog(100, 79228162514264337593543950336, 1e18, 500, 1)
        );
        inverseReactive.react(
            _swapLog(100, 79228162514264337593543950336, 1e18, 500, 1)
        );

        vm.warp(160);
        reactive.react(
            _swapLog(200, 79625275426524748796330556128, 1e18, 500, 2)
        );
        inverseReactive.react(
            _swapLog(200, 79625275426524748796330556128, 1e18, 500, 2)
        );

        vm.warp(220);
        (int24 directTick, bool directReady) = reactive.getTick();
        (uint256 directPrice, bool directPriceReady) = reactive.getPriceE18();
        (int24 inverseTick, bool inverseReady) = inverseReactive.getTick();
        (uint256 inversePrice, bool inversePriceReady) = inverseReactive
            .getPriceE18();

        assertTrue(directReady);
        assertTrue(directPriceReady);
        assertTrue(inverseReady);
        assertTrue(inversePriceReady);
        assertEq(directTick, 150);
        assertEq(inverseTick, -150);
        assertEq(directPrice, _priceAtTick(150, 18, 18));
        assertEq(inversePrice, _priceAtTick(-150, 18, 18));
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

    function _swapLog(
        int24 tick,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint24 fee,
        uint256 blockNumber
    ) internal view returns (IReactive.LogRecord memory log) {
        log.chain_id = SOURCE_CHAIN_ID;
        log._contract = POOL_MANAGER;
        log.topic_0 = uint256(reactive.SWAP_TOPIC());
        log.topic_1 = uint256(POOL_ID);
        log.topic_2 = uint256(uint160(address(0x1111)));
        log.data = abi.encode(
            int128(1e18),
            int128(-1e18),
            sqrtPriceX96,
            liquidity,
            tick,
            fee
        );
        log.block_number = blockNumber;
    }
}
