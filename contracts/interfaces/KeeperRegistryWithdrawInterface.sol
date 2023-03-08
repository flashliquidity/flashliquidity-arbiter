//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface KeeperRegistryWithdrawInterface {
    function withdrawFunds(uint256 _id, address _to) external;
}
