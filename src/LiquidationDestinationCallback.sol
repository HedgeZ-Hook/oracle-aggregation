// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {AbstractCallback} from "@reactive/abstract-base/AbstractCallback.sol";
import {IVammClearingHouse} from "./interfaces/IVammClearingHouse.sol";
import {IVammOracle} from "./interfaces/IVammOracle.sol";

contract LiquidationDestinationCallback is AbstractCallback {
    event LiquidationSuccess(address indexed trader);
    IVammOracle public oracleContract;
    IVammClearingHouse public clearingHouseContract;

    constructor(
        address _oracleContract,
        address _clearingHouseContract,
        address _callbackSender
    ) payable AbstractCallback(_callbackSender) {
        oracleContract = IVammOracle(_oracleContract);
        clearingHouseContract = IVammClearingHouse(_clearingHouseContract);
    }

    function updateOraclePrice(
        uint256 _priceE18
    ) external authorizedSenderOnly {
        if (address(oracleContract) != address(0)) {
            oracleContract.updateOraclePrice(_priceE18);
        }
    }

    function liquidate(address _trader) external authorizedSenderOnly {
        if (address(clearingHouseContract) != address(0)) {
            clearingHouseContract.liquidate(_trader);
        }
        emit LiquidationSuccess(_trader);
    }
}
