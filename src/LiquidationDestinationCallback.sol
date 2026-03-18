// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {AbstractCallback} from "@reactive/abstract-base/AbstractCallback.sol";
import {IVammLiquidityController} from "./interfaces/IVammLiquidityController.sol";
import {IVammClearingHouse} from "./interfaces/IVammClearingHouse.sol";
import {IVammOracle} from "./interfaces/IVammOracle.sol";
import {IVammVault} from "./interfaces/IVammVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LiquidationDestinationCallback is AbstractCallback, Ownable {
    address public trustedAggregator;
    address public traderUpdater;
    uint256 public latestOraclePriceE18;

    mapping(address => uint256) public liquidationPriceE18;
    mapping(address => uint256) public tradersIdx;
    address[] public traders;

    event TraderRemoved(address indexed trader, uint256 liquidationPriceE18);
    event OraclePriceUpdated(
        address indexed aggregator,
        uint256 previousOraclePriceE18,
        uint256 latestOraclePriceE18,
        uint256 activePools
    );
    event Repriced(bool executed, bool zeroForOne, uint256 usedAmountIn);
    IVammClearingHouse public clearingHouseContract;
    IVammVault public vaultContract;
    IVammLiquidityController public liquidityControllerContract;

    modifier onlyClearingHouse() {
        require(msg.sender == address(clearingHouseContract), "bad sender");
        _;
    }

    constructor(
        address _clearingHouseContract,
        address _liquidityControllerContract,
        address _callbackSender
    ) payable AbstractCallback(_callbackSender) Ownable(msg.sender) {
        clearingHouseContract = IVammClearingHouse(_clearingHouseContract);
        liquidityControllerContract = IVammLiquidityController(
            _liquidityControllerContract
        );
    }

    function traderCount() external view returns (uint256) {
        return traders.length;
    }

    function setTrustedAggregator(
        address _trustedAggregator
    ) external onlyOwner {
        trustedAggregator = _trustedAggregator;
    }

    function setTraderUpdater(address _traderUpdater) external onlyOwner {
        traderUpdater = _traderUpdater;
    }

    function setClearingHouseContract(
        address _clearingHouseContract
    ) external onlyOwner {
        clearingHouseContract = IVammClearingHouse(_clearingHouseContract);
    }

    function setVaultContract(address _vaultContract) external onlyOwner {
        vaultContract = IVammVault(_vaultContract);
    }

    function setLiquidityControllerContract(
        address _liquidityControllerContract
    ) external onlyOwner {
        liquidityControllerContract = IVammLiquidityController(
            _liquidityControllerContract
        );
    }

    function updateTrader(
        address trader,
        uint256 liquidationPrice,
        bool isLiquidated
    ) external onlyClearingHouse {
        if (liquidationPrice == 0 && isLiquidated) {
            _removeTrader(trader);
            return;
        }

        liquidationPriceE18[trader] = liquidationPrice;
        if (tradersIdx[trader] == 0) {
            traders.push(trader);
            tradersIdx[trader] = traders.length;
        }
    }

    function onAggregatedPrice(
        address, // rvmId overwritten by Reactive
        address aggregator,
        uint256 currentPriceE18,
        uint256 activePools
    ) external authorizedSenderOnly {
        require(
            trustedAggregator == address(0) || aggregator == trustedAggregator,
            "bad aggregator"
        );
        if (activePools == 0 || currentPriceE18 == 0) {
            return;
        }

        uint256 previousOraclePriceE18 = latestOraclePriceE18;
        latestOraclePriceE18 = currentPriceE18;

        if (address(liquidityControllerContract) != address(0)) {
            try liquidityControllerContract.updateFromOracle() returns (
                bool executed,
                bool zeroForOne,
                uint256 usedAmountIn
            ) {
                emit Repriced(executed, zeroForOne, usedAmountIn);
            } catch {
                emit Repriced(false, false, 0);
            }
        }

        // @dev: Since it is just demo, so this function can be inefficient,
        // in production, we have to find another way for fetching liquidated users
        // Ex: It can be implementing balanced sorted tree for quick searching
        // When we have like 1M users, this function can be out of gas.
        // So another method should be implement to liquidate gradually by time to time
        uint256 i = 0;
        while (i < traders.length) {
            address trader = traders[i];
            if (address(vaultContract) == address(0)) {
                unchecked {
                    ++i;
                }
                continue;
            }
            if (!vaultContract.isLiquidatable(trader)) {
                unchecked {
                    ++i;
                }
                continue;
            }

            if (address(clearingHouseContract) != address(0)) {
                bool isFullyLiquidated;
                try clearingHouseContract.liquidate(trader) returns (
                    bool liquidated,
                    uint256,
                    uint256
                ) {
                    isFullyLiquidated = liquidated;
                } catch {
                    unchecked {
                        ++i;
                    }
                    continue;
                }

                if (isFullyLiquidated) {
                    if (i < traders.length && traders[i] == trader) {
                        unchecked {
                            ++i;
                        }
                    }
                    continue;
                }
            }

            unchecked {
                ++i;
            }
        }

        emit OraclePriceUpdated(
            aggregator,
            previousOraclePriceE18,
            currentPriceE18,
            activePools
        );
    }

    function _removeTrader(address trader) internal {
        uint256 traderIdx = tradersIdx[trader];
        uint256 liquidationPrice = liquidationPriceE18[trader];
        delete liquidationPriceE18[trader];

        if (traderIdx == 0) {
            return;
        }

        uint256 index = traderIdx - 1;
        uint256 lastIndex = traders.length - 1;
        if (index != lastIndex) {
            address movedTrader = traders[lastIndex];
            traders[index] = movedTrader;
            tradersIdx[movedTrader] = index + 1;
        }

        traders.pop();
        delete tradersIdx[trader];

        emit TraderRemoved(trader, liquidationPrice);
    }
}
