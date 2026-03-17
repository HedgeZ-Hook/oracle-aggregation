// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {AbstractCallback} from "@reactive/abstract-base/AbstractCallback.sol";
import {IVammClearingHouse} from "./interfaces/IVammClearingHouse.sol";
import {IVammOracle} from "./interfaces/IVammOracle.sol";
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
    IVammOracle public oracleContract;
    IVammClearingHouse public clearingHouseContract;

    modifier onlyClearingHouse() {
        require(msg.sender == address(clearingHouseContract), "bad sender");
        _;
    }

    constructor(
        address _oracleContract,
        address _clearingHouseContract,
        address _callbackSender
    ) payable AbstractCallback(_callbackSender) Ownable(msg.sender) {
        oracleContract = IVammOracle(_oracleContract);
        clearingHouseContract = IVammClearingHouse(_clearingHouseContract);
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

    function setOracleContract(address _oracleContract) external onlyOwner {
        oracleContract = IVammOracle(_oracleContract);
    }

    function setClearingHouseContract(
        address _clearingHouseContract
    ) external onlyOwner {
        clearingHouseContract = IVammClearingHouse(_clearingHouseContract);
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

        // @dev: Since it is just demo, so this function can be inefficient,
        // in production, we have to find another way for fetching liquidated users
        // Ex: It can be implementing balanced sorted tree for quick searching
        // When we have like 1M users, this function can be out of gas.
        // So another method should be implement to liquidate gradually by time to time
        uint256 i = 0;
        while (i < traders.length) {
            address trader = traders[i];
            uint256 liquidationPrice = liquidationPriceE18[trader];
            if (liquidationPrice == 0 || liquidationPrice <= currentPriceE18) {
                unchecked {
                    ++i;
                }
                continue;
            }

            if (address(clearingHouseContract) != address(0)) {
                (bool liquidated, , ) = clearingHouseContract.liquidate(trader);

                if (liquidated) {
                    _removeTrader(trader);
                }
            }
        }

        if (address(oracleContract) != address(0)) {
            oracleContract.updateOraclePrice(currentPriceE18);
        }
        emit OraclePriceUpdated(
            aggregator,
            previousOraclePriceE18,
            currentPriceE18,
            activePools
        );
    }

    function updateOraclePrice(
        uint256 _priceE18
    ) external authorizedSenderOnly {
        latestOraclePriceE18 = _priceE18;
        if (address(oracleContract) != address(0)) {
            oracleContract.updateOraclePrice(_priceE18);
        }
    }

    function liquidate(address _trader) external authorizedSenderOnly {
        if (address(clearingHouseContract) != address(0)) {
            clearingHouseContract.liquidate(_trader);
        }
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
