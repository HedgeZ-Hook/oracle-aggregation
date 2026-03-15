// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {BasicDemoReactiveContract} from "../src/DemoReactive.sol";

contract DeployDemoReactiveLasna is Script {
    address internal constant SYSTEM_CONTRACT_ADDR =
        0x0000000000000000000000000000000000fffFfF;
    uint256 internal constant ORIGIN_CHAIN_ID = 11155111;
    uint256 internal constant DESTINATION_CHAIN_ID = 11155111;
    address internal constant ORIGIN_ADDR =
        0xE914e453c4c97B81893e547978D8F4f8835EA83E;
    uint256 internal constant TOPIC_0 =
        0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67;
    address internal constant CALLBACK_ADDR =
        0xAff042e95b1C99c1DB304bA4701ac1C1bA05A410;

    function run() external returns (BasicDemoReactiveContract deployed) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 deployValue = vm.envOr("DEPLOY_VALUE", uint256(1 ether));

        vm.startBroadcast(deployerPrivateKey);
        deployed = new BasicDemoReactiveContract{value: deployValue}(
            SYSTEM_CONTRACT_ADDR,
            ORIGIN_CHAIN_ID,
            DESTINATION_CHAIN_ID,
            ORIGIN_ADDR,
            TOPIC_0,
            CALLBACK_ADDR
        );
        vm.stopBroadcast();

        console2.log("BasicDemoReactiveContract:", address(deployed));
        console2.log("Reactive network chain id:", block.chainid);
        console2.log("System contract:", SYSTEM_CONTRACT_ADDR);
        console2.log("Origin chain id:", ORIGIN_CHAIN_ID);
        console2.log("Destination chain id:", DESTINATION_CHAIN_ID);
        console2.log("Origin contract:", ORIGIN_ADDR);
        console2.log("Topic0:", TOPIC_0);
        console2.log("Callback:", CALLBACK_ADDR);
        console2.log("Deploy value:", deployValue);
    }
}
