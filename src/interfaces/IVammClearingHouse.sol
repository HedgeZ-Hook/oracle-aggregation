// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IVammClearingHouse {
    function liquidate(address user) external;
}
