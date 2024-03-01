// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

contract BalancerV2VaultMock {

    mapping(bytes32 poolId => IERC20[] tokens) s_poolToTokens;

    constructor() {}

    function addPool(bytes32 poolId, address[] memory tokens) external {
        for(uint i = 0; i < tokens.length; i++) {
            s_poolToTokens[poolId].push(IERC20(tokens[i]));
        }
    }

    function getPoolTokens(bytes32 poolId) external view returns(IERC20[] memory, uint256[] memory balances, uint256 lastChangeBlock) {
        return (s_poolToTokens[poolId], new uint256[](0), 0);
    }
    
    // skip coverage
    function test() external {}
}

