// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IReactive} from "@reactive/interfaces/IReactive.sol";

import {FullMath} from "../src/libraries/FullMath.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {MockLiquidationExecutorCallback} from "../src/MockLiquidationExecutorCallback.sol";
import {LiquidationMonitorReactive} from "../src/LiquidationMonitorReactive.sol";
import {PriceAggregationReactive} from "../src/PriceAggregationReactive.sol";
import {console2} from "forge-std/console2.sol";

contract LiquidationFlowTest is Test {
    event Callback(
        uint256 indexed chain_id,
        address indexed _contract,
        uint64 indexed gas_limit,
        bytes payload
    );

    uint256 internal constant SOURCE_CHAIN_ID = 8453;
    uint256 internal constant REACTIVE_CHAIN_ID = 5318008;
    address internal constant SERVICE_ADDR =
        0x0000000000000000000000000000000000fffFfF;
    address internal constant POOL_A = address(0x1111);
    address internal constant POOL_B = address(0x2222);
    address internal constant LIQUIDATION_SOURCE = address(0x3333);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    int24 internal constant ETH_USDC_3100_TICK = -195928;
    int24 internal constant ETH_USDC_3000_TICK = -196256;
    int24 internal constant ETH_USDC_2999_TICK = -196257;
    int24 internal constant ETH_USDC_2980_TICK = -196323;
    int24 internal constant ETH_USDC_2995_TICK = -196273;

    MockLiquidationExecutorCallback internal executor;
    LiquidationMonitorReactive internal monitor;
    PriceAggregationReactive internal aggregator;

    function setUp() external {
        vm.chainId(REACTIVE_CHAIN_ID);

        executor = new MockLiquidationExecutorCallback(SERVICE_ADDR);

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
            token0Decimals: 18,
            token1Decimals: 6,
            useQuoteAsBase: false,
            weight: 10
        });

        monitor = new LiquidationMonitorReactive(
            SOURCE_CHAIN_ID,
            LIQUIDATION_SOURCE,
            address(0x1234), // placeholder, overwritten after aggregator deploy
            address(executor),
            REACTIVE_CHAIN_ID,
            300_000
        );

        aggregator = new PriceAggregationReactive(
            120,
            poolConfigs,
            REACTIVE_CHAIN_ID,
            address(monitor),
            400_000
        );

        monitor = new LiquidationMonitorReactive(
            SOURCE_CHAIN_ID,
            LIQUIDATION_SOURCE,
            address(aggregator),
            address(executor),
            REACTIVE_CHAIN_ID,
            300_000
        );
    }

    function testIntegrationFullFlow() external {
        vm.warp(100);
        aggregator.react(_swapLog(POOL_A, ETH_USDC_3100_TICK, 1));
        aggregator.react(_swapLog(POOL_B, ETH_USDC_3100_TICK, 1));

        (
            uint256 priceAt3100,
            bool readyAt3100,
            uint256 activeAt3100
        ) = aggregator.getAggregatePriceE18(0);
        assertTrue(readyAt3100);
        assertEq(activeAt3100, 2);
        assertApproxEqAbs(priceAt3100, 3100e18, 3e17);

        address[10] memory traders_;
        for (uint256 i = 0; i < 10; ++i) {
            traders_[i] = address(uint160(0x1000 + i));
        }

        for (uint256 i = 0; i < 5; ++i) {
            monitor.react(_liquidationUpdateLog(traders_[i], 3001e18));
        }
        for (uint256 i = 5; i < 10; ++i) {
            monitor.react(_liquidationUpdateLog(traders_[i], 2990e18));
        }

        vm.warp(101);
        aggregator.react(_swapLog(POOL_B, ETH_USDC_2980_TICK, 2));

        (uint256 priceA, ) = aggregator.getPoolPriceE18(
            keccak256(abi.encode(SOURCE_CHAIN_ID, POOL_A))
        );
        (uint256 priceB, ) = aggregator.getPoolPriceE18(
            keccak256(abi.encode(SOURCE_CHAIN_ID, POOL_B))
        );
        (
            uint256 priceAfterBOnly,
            bool readyAfterBOnly,
            uint256 activeAfterBOnly
        ) = aggregator.getAggregatePriceE18(0);

        assertTrue(readyAfterBOnly);
        assertEq(activeAfterBOnly, 2);
        console2.log("priceA", priceA);
        console2.log("priceB", priceB);
        console2.log("priceAfterBOnly", priceAfterBOnly);
        assertTrue(priceAfterBOnly > 3001e18);

        vm.recordLogs();
        vm.prank(SERVICE_ADDR);
        monitor.onAggregatedPrice(
            address(aggregator),
            priceAfterBOnly,
            activeAfterBOnly
        );
        Vm.Log[] memory logsAfterBOnly = vm.getRecordedLogs();
        assertEq(_countCallbackLogs(logsAfterBOnly, address(monitor)), 0);

        vm.warp(102);
        aggregator.react(_swapLog(POOL_A, ETH_USDC_2995_TICK, 3));

        (
            uint256 priceAfterABreak,
            bool readyAfterABreak,
            uint256 activeAfterABreak
        ) = aggregator.getAggregatePriceE18(0);
        assertTrue(readyAfterABreak);
        assertEq(activeAfterABreak, 2);
        assertTrue(priceAfterABreak < 3000e18);
        assertTrue(priceAfterABreak > 2990e18);
        assertApproxEqAbs(priceAfterABreak, 2993500000000000000000, 4e17);

        vm.recordLogs();
        vm.prank(SERVICE_ADDR);
        monitor.onAggregatedPrice(
            address(aggregator),
            priceAfterABreak,
            activeAfterABreak
        );
        Vm.Log[] memory liquidationRequestLogs = vm.getRecordedLogs();
        assertEq(
            _countCallbackLogs(liquidationRequestLogs, address(monitor)),
            5
        );

        for (uint256 i = 0; i < 5; ++i) {
            vm.prank(SERVICE_ADDR);
            executor.liquidateTrader(traders_[i]);
            monitor.react(_liquidatedLog(traders_[i]));
        }

        assertEq(monitor.traderCount(), 5);
        for (uint256 i = 0; i < 5; ++i) {
            assertEq(monitor.liquidationPriceE18(traders_[i]), 0);
            assertEq(monitor.traderIndexPlusOne(traders_[i]), 0);
        }
        for (uint256 i = 5; i < 10; ++i) {
            assertEq(monitor.liquidationPriceE18(traders_[i]), 2990e18);
            assertTrue(monitor.traderIndexPlusOne(traders_[i]) > 0);
        }

        vm.warp(103);
        aggregator.react(_swapLog(POOL_B, ETH_USDC_2995_TICK, 4));

        (
            uint256 priceAfterArb,
            bool readyAfterArb,
            uint256 activeAfterArb
        ) = aggregator.getAggregatePriceE18(0);
        assertTrue(readyAfterArb);
        assertEq(activeAfterArb, 2);
        assertApproxEqAbs(priceAfterArb, 2995e18, 3e17);
        assertTrue(priceAfterArb > 2990e18);

        vm.recordLogs();
        vm.prank(SERVICE_ADDR);
        monitor.onAggregatedPrice(
            address(aggregator),
            priceAfterArb,
            activeAfterArb
        );
        Vm.Log[] memory logsAfterArb = vm.getRecordedLogs();
        assertEq(_countCallbackLogs(logsAfterArb, address(monitor)), 0);
        assertEq(monitor.traderCount(), 5);
    }

    function _swapLog(
        address pool,
        int24 tick,
        uint256 blockNumber
    ) internal view returns (IReactive.LogRecord memory log) {
        return _swapLogFor(aggregator, pool, tick, blockNumber);
    }

    function _swapLogFor(
        PriceAggregationReactive targetAggregator,
        address pool,
        int24 tick,
        uint256 blockNumber
    ) internal view returns (IReactive.LogRecord memory log) {
        log.chain_id = SOURCE_CHAIN_ID;
        log._contract = pool;
        log.topic_0 = uint256(targetAggregator.V3_SWAP_TOPIC());
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

    function _liquidationUpdateLog(
        address trader,
        uint256 liquidationPrice
    ) internal view returns (IReactive.LogRecord memory log) {
        return _liquidationUpdateLogFor(monitor, trader, liquidationPrice);
    }

    function _liquidationUpdateLogFor(
        LiquidationMonitorReactive targetMonitor,
        address trader,
        uint256 liquidationPrice
    ) internal view returns (IReactive.LogRecord memory log) {
        log.chain_id = SOURCE_CHAIN_ID;
        log._contract = LIQUIDATION_SOURCE;
        log.topic_0 = uint256(targetMonitor.TRADER_LIQUIDATION_UPDATE_TOPIC());
        log.data = abi.encode(trader, liquidationPrice);
    }

    function _liquidatedLog(
        address trader
    ) internal view returns (IReactive.LogRecord memory log) {
        return _liquidatedLogFor(monitor, executor, trader);
    }

    function _liquidatedLogFor(
        LiquidationMonitorReactive targetMonitor,
        MockLiquidationExecutorCallback targetExecutor,
        address trader
    ) internal view returns (IReactive.LogRecord memory log) {
        log.chain_id = REACTIVE_CHAIN_ID;
        log._contract = address(targetExecutor);
        log.topic_0 = uint256(targetMonitor.TRADER_LIQUIDATED_TOPIC());
        log.topic_1 = uint256(uint160(trader));
    }

    function _countCallbackLogs(
        Vm.Log[] memory logs,
        address emitter
    ) internal pure returns (uint256 count) {
        bytes32 callbackTopic = keccak256(
            "Callback(uint256,address,uint64,bytes)"
        );

        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == emitter &&
                logs[i].topics.length > 0 &&
                logs[i].topics[0] == callbackTopic
            ) {
                count++;
            }
        }
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
