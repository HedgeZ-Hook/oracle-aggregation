// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

contract MockChainlinkAggregator {
    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    function pushAnswer(int256 current, uint256 roundId, uint256 updatedAt) external {
        emit AnswerUpdated(current, roundId, updatedAt);
    }
}
