// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IUpkeepsStationV3 {
    error OutOfBound();
    error RefuelNotNeeded();
    error InvalidPerformData();
    error InvalidCheckData();

    event UpkeepRegistered(uint256 indexed _id);
    event UpkeepRemoved(uint256 indexed _id);
    event UpkeepRefueled(uint256 indexed _id, uint96 indexed _amount);

    function setMinUpkeepBalance(uint96 _minUpkeepBalance) external;

    function setToUpkeepAmount(uint96 _toUpkeepAmount) external;

    function initialize(uint96 _amount) external;

    function selfDismantle() external;

    function withdrawStationUpkeep() external;

    function addArbiterUpkeep(uint96 _amount) external;

    function addUpkeep(
        string calldata _name,
        address _target,
        uint32 _gasLimit,
        bytes calldata _checkData,
        uint96 _amount
    ) external;

    function removeArbiterUpkeep() external;

    function removeUpkeep(uint256 _index) external;

    function withdrawCanceledUpkeeps(uint256 _upkeepsNumber) external;
}
