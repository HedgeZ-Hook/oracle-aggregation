// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {UniswapV3TickTwap} from "../src/UniswapV3TickTwapReactive.sol";

contract InteractUniswapV3TickTwap is Script {
    address payable internal constant CONTRACT_ADDR =
        payable(0x8d421646f0Bddd607d6C6b9cf9466F3B7003D486);

    function showState() external view {
        UniswapV3TickTwap target = UniswapV3TickTwap(CONTRACT_ADDR);

        (int24 tick, bool tickReady) = target.getTick();
        (uint256 priceE18, bool priceReady) = target.getPriceE18();

        console2.log("Contract:", CONTRACT_ADDR);
        console2.log("Source chain id:", target.sourceChainId());
        console2.log("Pool:", target.pool());
        console2.log("Base decimals:", uint256(target.baseDecimals()));
        console2.log("Quote decimals:", uint256(target.quoteDecimals()));
        console2.log("Use quote as base:", target.useQuoteAsBase());
        console2.log("Initialized:", target.initialized());
        console2.log("Latest tick:", int256(target.latestTick()));
        console2.log("Latest tick timestamp:", target.latestTickTimestamp());
        console2.log(
            "Current observation index:",
            uint256(target.currentObservationIndex())
        );
        console2.log("Tick:", int256(tick));
        console2.log("Tick ready:", tickReady);
        console2.log("Price E18:", priceE18);
        console2.log("Price ready:", priceReady);
    }

    function pauseContract() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        UniswapV3TickTwap(CONTRACT_ADDR).pause();
        vm.stopBroadcast();
    }

    function resumeContract() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        UniswapV3TickTwap(CONTRACT_ADDR).resume();
        vm.stopBroadcast();
    }

    function coverDebt() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        UniswapV3TickTwap(CONTRACT_ADDR).coverDebt();
        vm.stopBroadcast();
    }
}
