// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.0;

import {TickCumulativeTwap} from "./TickCumulativeTwap.sol";

abstract contract CachedTickTwap is TickCumulativeTwap {
    int24 internal _cachedAverageTick;
    uint160 internal _lastUpdatedAt;
    uint80 internal _interval;

    constructor(uint80 interval) {
        _interval = interval;
    }

    function _cacheAverageTick(uint256 interval, int24 latestTick, uint256 latestUpdatedTimestamp)
        internal
        virtual
        returns (int24)
    {
        _updateTick(latestTick, latestUpdatedTimestamp);

        if (_interval != interval) {
            return interval == 0 ? latestTick : _getAverageTick(interval, latestTick, latestUpdatedTimestamp);
        }

        if (_blockTimestamp() != _lastUpdatedAt) {
            _lastUpdatedAt = uint160(_blockTimestamp());
            _cachedAverageTick = _getAverageTick(interval, latestTick, latestUpdatedTimestamp);
        }

        return _cachedAverageTick;
    }

    function _getCachedAverageTick(uint256 interval, int24 latestTick, uint256 latestUpdatedTimestamp)
        internal
        view
        returns (int24)
    {
        if (_blockTimestamp() == _lastUpdatedAt && interval == _interval) {
            return _cachedAverageTick;
        }

        return _getAverageTick(interval, latestTick, latestUpdatedTimestamp);
    }

    function _getAverageTick(uint256 interval, int24 latestTick, uint256 latestUpdatedTimestamp)
        internal
        view
        returns (int24)
    {
        (int24 averageTick, bool hasTwap) = _calculateAverageTick(interval, latestTick, latestUpdatedTimestamp);
        return hasTwap ? averageTick : latestTick;
    }

    function _getPriceTwap(
        uint256 interval,
        int24 latestTick,
        uint256 latestUpdatedTimestamp,
        uint8 baseDecimals,
        uint8 quoteDecimals
    ) internal view returns (uint256) {
        (uint256 priceE18, bool hasTwap) =
            _calculatePriceTwap(interval, latestTick, latestUpdatedTimestamp, baseDecimals, quoteDecimals);
        return hasTwap ? priceE18 : _priceAtTick(latestTick, baseDecimals, quoteDecimals);
    }
}
