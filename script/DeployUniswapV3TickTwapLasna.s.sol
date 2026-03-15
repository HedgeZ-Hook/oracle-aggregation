// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {UniswapV3TickTwap} from "../src/UniswapV3TickTwapReactive.sol";

contract DeployUniswapV3TickTwapLasna is Script {
    uint256 internal constant CHAIN_ID = 8453;
    address internal constant ETH_USDC_POOL =
        0x6c561B446416E1A00E8E93E221854d6eA4171372;
    uint8 internal constant BASE_DECIMALS = 18;
    uint8 internal constant QUOTE_DECIMALS = 6;
    uint80 internal constant DEFAULT_INTERVAL = 900;
    uint256 internal constant DEFAULT_DEPLOY_VALUE = 50 ether;

    function run() external returns (UniswapV3TickTwap deployed) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint80 interval = uint80(
            vm.envOr("TWAP_INTERVAL", uint256(DEFAULT_INTERVAL))
        );
        uint256 deployValue = vm.envOr("DEPLOY_VALUE", DEFAULT_DEPLOY_VALUE);

        vm.startBroadcast(deployerPrivateKey);
        deployed = new UniswapV3TickTwap{value: deployValue}(
            CHAIN_ID,
            ETH_USDC_POOL,
            interval,
            BASE_DECIMALS,
            QUOTE_DECIMALS,
            false
        );
        vm.stopBroadcast();

        console2.log("UniswapV3TickTwap:", address(deployed));
        console2.log("Reactive network chain id:", block.chainid);
        console2.log("Source chain id:", CHAIN_ID);
        console2.log("Pool:", ETH_USDC_POOL);
        console2.log("Interval:", uint256(interval));
        console2.log("Deploy value:", deployValue);
    }
}
