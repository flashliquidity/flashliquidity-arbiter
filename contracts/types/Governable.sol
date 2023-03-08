//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Governable {
    address public governor;
    address public pendingGovernor;
    uint256 public govTransferReqTimestamp;
    uint256 public immutable transferGovernanceDelay;

    error ZeroAddress();
    error NotAuthorized();
    error TooEarly();

    event GovernanceTrasferred(address indexed _oldGovernor, address indexed _newGovernor);
    event PendingGovernorChanged(address indexed _pendingGovernor);

    constructor(address _governor, uint256 _transferGovernanceDelay) {
        governor = _governor;
        transferGovernanceDelay = _transferGovernanceDelay;
        emit GovernanceTrasferred(address(0), _governor);
    }

    function setPendingGovernor(address _pendingGovernor) external onlyGovernor {
        if (_pendingGovernor == address(0)) revert ZeroAddress();
        pendingGovernor = _pendingGovernor;
        govTransferReqTimestamp = block.timestamp;
        emit PendingGovernorChanged(_pendingGovernor);
    }

    function transferGovernance() external {
        address _newGovernor = pendingGovernor;
        address _oldGovernor = governor;
        if (_newGovernor == address(0)) revert ZeroAddress();
        if (msg.sender != _oldGovernor && msg.sender != _newGovernor) revert NotAuthorized();
        if (block.timestamp - govTransferReqTimestamp < transferGovernanceDelay) revert TooEarly();
        pendingGovernor = address(0);
        governor = _newGovernor;
        emit GovernanceTrasferred(_oldGovernor, _newGovernor);
    }

    modifier onlyGovernor() {
        if (msg.sender != governor) revert NotAuthorized();
        _;
    }
}
