//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Governable} from "./Governable.sol";

abstract contract BastionConnector is Governable {
    using SafeERC20 for IERC20;
    address public bastion;
    event TransferredToBastion(address[] indexed _tokens, uint256[] indexed _amounts);

    constructor(
        address _governor,
        address _bastion,
        uint256 _transferGovernanceDelay
    ) Governable(_governor, _transferGovernanceDelay) {
        bastion = _bastion;
    }

    function transferToBastion(
        address[] calldata _tokens,
        uint256[] calldata _amounts
    ) external onlyGovernor {
        for (uint256 i = 0; i < _tokens.length; ) {
            IERC20(_tokens[i]).safeTransfer(bastion, _amounts[i]);
            unchecked {
                i++;
            }
        }
        emit TransferredToBastion(_tokens, _amounts);
    }
}
