// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";

import {TickMath} from "../src/libraries/TickMath.sol";
import {LiquidationDestinationCallback} from "../src/LiquidationDestinationCallback.sol";
import {PriceAggregationReactive} from "../src/PriceAggregationReactive.sol";
import {ITraderMonitor} from "../src/interfaces/ITraderMonitor.sol";

contract MockOracle {
    uint256 public lastPriceE18;

    function updateOraclePrice(uint256 priceE18) external {
        lastPriceE18 = priceE18;
    }
}

contract MockVault {
    mapping(address => bool) public liquidatable;

    function setLiquidatable(address trader, bool value) external {
        liquidatable[trader] = value;
    }

    function isLiquidatable(address trader) external view returns (bool) {
        return liquidatable[trader];
    }
}

contract MockClearingHouse {
    ITraderMonitor public traderMonitor;

    constructor(address _traderMonitor) {
        traderMonitor = ITraderMonitor(_traderMonitor);
    }

    function updateTrader(
        address trader,
        uint256 liquidationPrice,
        bool isLiquidated
    ) external {
        traderMonitor.updateTrader(trader, liquidationPrice, isLiquidated);
    }

    function liquidate(
        address trader
    ) external returns (bool, uint256, uint256) {
        traderMonitor.updateTrader(trader, 0, true);
        return (true, 0, 0);
    }
}

contract LiquidationFlowTest is Test {
    uint256 internal constant SOURCE_CHAIN_ID = 8453;
    uint256 internal constant REACTIVE_CHAIN_ID = 5318008;
    address internal constant SERVICE_ADDR =
        0x0000000000000000000000000000000000fffFfF;
    address internal constant POOL_A = address(0x1111);
    address internal constant POOL_B = address(0x2222);
    int24 internal constant ETH_USDC_3100_TICK = -195928;
    int24 internal constant ETH_USDC_2980_TICK = -196323;
    int24 internal constant ETH_USDC_2995_TICK = -196273;

    MockOracle internal oracle;
    MockVault internal vault;
    MockClearingHouse internal clearingHouse;
    LiquidationDestinationCallback internal destination;
    PriceAggregationReactive internal aggregator;

    function setUp() external {
        vm.chainId(REACTIVE_CHAIN_ID);

        oracle = new MockOracle();
        vault = new MockVault();
        destination = new LiquidationDestinationCallback(
            address(oracle),
            address(0),
            SERVICE_ADDR
        );
        clearingHouse = new MockClearingHouse(address(destination));
        destination.setClearingHouseContract(address(clearingHouse));
        destination.setVaultContract(address(vault));

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
            address(destination),
            400_000
        );
        destination.setTrustedAggregator(address(aggregator));
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
            clearingHouse.updateTrader(traders_[i], 3001e18, false);
            vault.setLiquidatable(traders_[i], false);
        }
        for (uint256 i = 5; i < 10; ++i) {
            clearingHouse.updateTrader(traders_[i], 2990e18, false);
            vault.setLiquidatable(traders_[i], false);
        }
        assertEq(destination.traderCount(), 10);

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

        vm.prank(SERVICE_ADDR);
        destination.onAggregatedPrice(
            address(0xdead),
            address(aggregator),
            priceAfterBOnly,
            activeAfterBOnly
        );
        assertEq(destination.latestOraclePriceE18(), priceAfterBOnly);
        assertEq(oracle.lastPriceE18(), priceAfterBOnly);
        assertEq(destination.traderCount(), 10);

        for (uint256 i = 0; i < 5; ++i) {
            vault.setLiquidatable(traders_[i], true);
        }

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

        vm.prank(SERVICE_ADDR);
        destination.onAggregatedPrice(
            address(0xdead),
            address(aggregator),
            priceAfterABreak,
            activeAfterABreak
        );
        assertEq(destination.latestOraclePriceE18(), priceAfterABreak);
        assertEq(oracle.lastPriceE18(), priceAfterABreak);
        assertEq(destination.traderCount(), 5);

        for (uint256 i = 0; i < 5; ++i) {
            assertEq(destination.liquidationPriceE18(traders_[i]), 0);
            assertEq(destination.tradersIdx(traders_[i]), 0);
        }
        for (uint256 i = 5; i < 10; ++i) {
            assertEq(destination.liquidationPriceE18(traders_[i]), 2990e18);
            assertTrue(destination.tradersIdx(traders_[i]) > 0);
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

        vm.prank(SERVICE_ADDR);
        destination.onAggregatedPrice(
            address(0xdead),
            address(aggregator),
            priceAfterArb,
            activeAfterArb
        );
        assertEq(oracle.lastPriceE18(), priceAfterArb);
        assertEq(destination.traderCount(), 5);
    }

    function testIntegrationReadyTrueAfterWarmup() external {
        address traderA = address(0xAAA1);
        address traderB = address(0xAAA2);

        vm.warp(100);
        aggregator.react(_swapLog(POOL_A, ETH_USDC_3100_TICK, 1));
        aggregator.react(_swapLog(POOL_B, ETH_USDC_3100_TICK, 1));

        clearingHouse.updateTrader(traderA, 3001e18, false);
        clearingHouse.updateTrader(traderB, 2990e18, false);
        vault.setLiquidatable(traderA, false);
        vault.setLiquidatable(traderB, false);

        vm.warp(221);
        aggregator.react(_swapLog(POOL_A, ETH_USDC_2995_TICK, 2));
        aggregator.react(_swapLog(POOL_B, ETH_USDC_2995_TICK, 2));

        (uint256 readyPrice, bool ready, uint256 activePools) = aggregator
            .getAggregatePriceE18();

        assertTrue(ready);
        assertEq(activePools, 2);
        assertTrue(readyPrice < 3101e18);
        assertTrue(readyPrice > 3000e18);

        vm.prank(SERVICE_ADDR);
        destination.onAggregatedPrice(
            address(0xdead),
            address(aggregator),
            readyPrice,
            activePools
        );
        assertEq(destination.latestOraclePriceE18(), readyPrice);
        assertEq(oracle.lastPriceE18(), readyPrice);
        assertEq(destination.traderCount(), 2);
        assertEq(destination.liquidationPriceE18(traderA), 3001e18);
        assertEq(destination.liquidationPriceE18(traderB), 2990e18);
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
}
