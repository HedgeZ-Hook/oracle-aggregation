// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IVammPerpHook } from "../interfaces/IVammPerpHook.sol";

contract MockVammPerpHook is IVammPerpHook {
    event PositionUpdated(
        bytes32 indexed marketId,
        address indexed account,
        int256 sizeE18,
        uint256 collateralUsdE18,
        uint256 entryPriceE18,
        bool isOpen
    );
    event PositionLiquidated(bytes32 indexed marketId, address indexed account);

    struct Position {
        int256 sizeE18;
        uint256 collateralUsdE18;
        uint256 entryPriceE18;
        bool isOpen;
    }

    mapping(bytes32 => mapping(address => Position)) public positions;

    function liquidate(address) external pure {
        revert("market id required");
    }

    function setPosition(
        bytes32 marketId,
        address account,
        int256 sizeE18,
        uint256 collateralUsdE18,
        uint256 entryPriceE18,
        bool isOpen
    ) external {
        positions[marketId][account] = Position({
            sizeE18: sizeE18,
            collateralUsdE18: collateralUsdE18,
            entryPriceE18: entryPriceE18,
            isOpen: isOpen
        });

        emit PositionUpdated(marketId, account, sizeE18, collateralUsdE18, entryPriceE18, isOpen);
    }

    function liquidatePosition(address account, bytes32 marketId) external {
        delete positions[marketId][account];
        emit PositionLiquidated(marketId, account);
    }
}
