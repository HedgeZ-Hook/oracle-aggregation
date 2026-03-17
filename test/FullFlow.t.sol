// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IReactive} from "@reactive/interfaces/IReactive.sol";

import {TickMath} from "../src/libraries/TickMath.sol";
import {LiquidationDestinationCallback} from "../src/LiquidationDestinationCallback.sol";
import {LiquidationMonitorReactive} from "../src/LiquidationMonitorReactive.sol";
import {PriceAggregationReactive} from "../src/PriceAggregationReactive.sol";

contract MockOracle {
    uint256 public lastPriceE18;

    function updateOraclePrice(uint256 priceE18) external {
        lastPriceE18 = priceE18;
    }
}

contract MockClearingHouse {
    mapping(address => bool) public liquidated;
    address[] public liquidatedTraders;

    function liquidate(address user) external {
        liquidated[user] = true;
        liquidatedTraders.push(user);
    }

    function liquidatedCount() external view returns (uint256) {
        return liquidatedTraders.length;
    }
}

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
    int24 internal constant ETH_USDC_3100_TICK = -195928;
    int24 internal constant ETH_USDC_2980_TICK = -196323;
    int24 internal constant ETH_USDC_2995_TICK = -196273;

    bytes4 internal constant UPDATE_ORACLE_SELECTOR =
        bytes4(keccak256("updateOraclePrice(uint256)"));
    bytes4 internal constant LIQUIDATE_SELECTOR =
        bytes4(keccak256("liquidate(address)"));

    MockOracle internal oracle;
    MockClearingHouse internal clearingHouse;
    LiquidationDestinationCallback internal destination;
    LiquidationMonitorReactive internal monitor;
    PriceAggregationReactive internal aggregator;

    function setUp() external {
        vm.chainId(REACTIVE_CHAIN_ID);

        oracle = new MockOracle();
        clearingHouse = new MockClearingHouse();
        destination = new LiquidationDestinationCallback(
            address(oracle),
            address(clearingHouse),
            SERVICE_ADDR
        );

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

        aggregator = new PriceAggregationReactive(
            120,
            poolConfigs,
            REACTIVE_CHAIN_ID,
            address(0),
            400_000
        );

        monitor = new LiquidationMonitorReactive(
            SOURCE_CHAIN_ID,
            LIQUIDATION_SOURCE,
            address(aggregator),
            REACTIVE_CHAIN_ID,
            address(destination),
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
            monitor.react(_liquidationPriceChangeLog(traders_[i], 3001e18, false));
        }
        for (uint256 i = 5; i < 10; ++i) {
            monitor.react(_liquidationPriceChangeLog(traders_[i], 2990e18, false));
        }

        vm.warp(101);
        aggregator.react(_swapLog(POOL_B, ETH_USDC_2980_TICK, 2));

        (
            uint256 priceAfterBOnly,
            bool readyAfterBOnly,
            uint256 activeAfterBOnly
        ) = aggregator.getAggregatePriceE18(0);
        assertTrue(readyAfterBOnly);
        assertEq(activeAfterBOnly, 2);
        assertTrue(priceAfterBOnly > 3001e18);

        vm.recordLogs();
        vm.prank(SERVICE_ADDR);
        monitor.onAggregatedPrice(
            address(aggregator),
            priceAfterBOnly,
            activeAfterBOnly
        );
        Vm.Log[] memory logsAfterBOnly = vm.getRecordedLogs();
        assertEq(
            _countCallbackLogsBySelector(
                logsAfterBOnly,
                address(monitor),
                UPDATE_ORACLE_SELECTOR
            ),
            1
        );
        assertEq(
            _countCallbackLogsBySelector(
                logsAfterBOnly,
                address(monitor),
                LIQUIDATE_SELECTOR
            ),
            0
        );

        vm.prank(SERVICE_ADDR);
        destination.updateOraclePrice(priceAfterBOnly);
        assertEq(oracle.lastPriceE18(), priceAfterBOnly);

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
            _countCallbackLogsBySelector(
                liquidationRequestLogs,
                address(monitor),
                UPDATE_ORACLE_SELECTOR
            ),
            1
        );
        assertEq(
            _countCallbackLogsBySelector(
                liquidationRequestLogs,
                address(monitor),
                LIQUIDATE_SELECTOR
            ),
            5
        );

        vm.prank(SERVICE_ADDR);
        destination.updateOraclePrice(priceAfterABreak);
        assertEq(oracle.lastPriceE18(), priceAfterABreak);

        for (uint256 i = 0; i < 5; ++i) {
            vm.prank(SERVICE_ADDR);
            destination.liquidate(traders_[i]);
            monitor.react(_liquidationPriceChangeLog(traders_[i], 0, true));
            assertTrue(clearingHouse.liquidated(traders_[i]));
        }

        assertEq(clearingHouse.liquidatedCount(), 5);
        assertEq(monitor.traderCount(), 5);
        for (uint256 i = 0; i < 5; ++i) {
            assertEq(monitor.liquidationPriceE18(traders_[i]), 0);
            assertEq(monitor.tradersIdx(traders_[i]), 0);
        }
        for (uint256 i = 5; i < 10; ++i) {
            assertEq(monitor.liquidationPriceE18(traders_[i]), 2990e18);
            assertTrue(monitor.tradersIdx(traders_[i]) > 0);
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
        assertEq(
            _countCallbackLogsBySelector(
                logsAfterArb,
                address(monitor),
                UPDATE_ORACLE_SELECTOR
            ),
            1
        );
        assertEq(
            _countCallbackLogsBySelector(
                logsAfterArb,
                address(monitor),
                LIQUIDATE_SELECTOR
            ),
            0
        );

        vm.prank(SERVICE_ADDR);
        destination.updateOraclePrice(priceAfterArb);
        assertEq(oracle.lastPriceE18(), priceAfterArb);
        assertEq(monitor.traderCount(), 5);
    }

    function testIntegrationReadyTrueAfterWarmup() external {
        address traderA = address(0xAAA1);
        address traderB = address(0xAAA2);

        vm.warp(100);
        aggregator.react(_swapLog(POOL_A, ETH_USDC_3100_TICK, 1));
        aggregator.react(_swapLog(POOL_B, ETH_USDC_3100_TICK, 1));

        monitor.react(_liquidationPriceChangeLog(traderA, 3001e18, false));
        monitor.react(_liquidationPriceChangeLog(traderB, 2990e18, false));

        vm.warp(221);
        aggregator.react(_swapLog(POOL_A, ETH_USDC_2995_TICK, 2));
        aggregator.react(_swapLog(POOL_B, ETH_USDC_2995_TICK, 2));

        (
            uint256 readyPrice,
            bool ready,
            uint256 activePools
        ) = aggregator.getAggregatePriceE18();

        assertTrue(ready);
        assertEq(activePools, 2);
        assertTrue(readyPrice < 3101e18);
        assertTrue(readyPrice > 3000e18);

        vm.recordLogs();
        vm.prank(SERVICE_ADDR);
        monitor.onAggregatedPrice(address(aggregator), readyPrice, activePools);
        Vm.Log[] memory callbackLogs = vm.getRecordedLogs();

        assertEq(
            _countCallbackLogsBySelector(
                callbackLogs,
                address(monitor),
                UPDATE_ORACLE_SELECTOR
            ),
            1
        );
        assertEq(
            _countCallbackLogsBySelector(
                callbackLogs,
                address(monitor),
                LIQUIDATE_SELECTOR
            ),
            0
        );

        vm.prank(SERVICE_ADDR);
        destination.updateOraclePrice(readyPrice);
        assertEq(oracle.lastPriceE18(), readyPrice);
        assertFalse(clearingHouse.liquidated(traderA));
        assertFalse(clearingHouse.liquidated(traderB));
        assertEq(monitor.traderCount(), 2);
        assertEq(monitor.liquidationPriceE18(traderA), 3001e18);
        assertEq(monitor.liquidationPriceE18(traderB), 2990e18);
    }

    function _swapLog(
        address pool,
        int24 tick,
        uint256 blockNumber
    ) internal view returns (IReactive.LogRecord memory log) {
        log.chain_id = SOURCE_CHAIN_ID;
        log._contract = pool;
        log.topic_0 = uint256(aggregator.V3_SWAP_TOPIC());
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

    function _liquidationPriceChangeLog(
        address trader,
        uint256 liquidationPrice,
        bool isLiquidated
    ) internal view returns (IReactive.LogRecord memory log) {
        log.chain_id = SOURCE_CHAIN_ID;
        log._contract = LIQUIDATION_SOURCE;
        log.topic_0 = uint256(monitor.LIQUIDATION_PRICE_CHANGE_TOPIC());
        log.data = abi.encode(trader, liquidationPrice, isLiquidated);
    }

    function _countCallbackLogsBySelector(
        Vm.Log[] memory logs,
        address emitter,
        bytes4 selector
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
                bytes memory payload = abi.decode(logs[i].data, (bytes));
                if (bytes4(payload) == selector) {
                    count++;
                }
            }
        }
    }
}
