//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IDexAdapter} from "../../../contracts/interfaces/IDexAdapter.sol";
/**
 * @title DexAdapter
 * @author Oddcod3 (@oddcod3)
 */

abstract contract DexAdapter is IDexAdapter {
    /// @dev Adapter description and version
    string public s_description;

    constructor(string memory description) {
        s_description = description;
    }

    /// @inheritdoc IDexAdapter
    function swap(
        address tokenIn,
        address tokenOut,
        address to,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes memory extraArgs
    ) external returns (uint256 amountOut) {
        amountOut = _swap(tokenIn, tokenOut, to, amountIn, amountOutMin, extraArgs);
    }

    /**
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param to The recipient of the swap
     * @param amountIn The amount of input tokens to be swapped.
     * @param amountOutMin The minimum amount out of output tokens below which the swap reverts.
     * @param extraArgs Adapter specific encoded extra arguments, used for providing additional instructions or data required by the specific DEX adapter.
     * @return amountOut The amount of output token received.
     * @notice Must be overridden for each concrete adapter with the correct implementation for the target DEX.
     */
    function _swap(
        address tokenIn,
        address tokenOut,
        address to,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes memory extraArgs
    ) internal virtual returns (uint256 amountOut);

    /**
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of input tokens to be swapped.
     * @return maxOutput The maximum amount of output tokens that can be received.
     * @return extraArgs Adapter specific encoded extra arguments, used for providing additional instructions or data required by the specific DEX adapter.
     * @notice Must be overridden for each concrete adapter with the correct implementation for the target DEX.
     */
    function _getMaxOutput(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        view
        virtual
        returns (uint256 maxOutput, bytes memory extraArgs);

    /**
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of input tokens to be swapped.
     * @param extraArgs Adapter specific encoded extra arguments, used for providing additional instructions or data required by the specific DEX adapter.
     */
    function _getOutputFromArgs(address tokenIn, address tokenOut, uint256 amountIn, bytes memory extraArgs)
        internal
        view
        virtual
        returns (uint256 amountOut);

    /**
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @return adapterArgs Array of adapter extraArgs given the tokenIn and tokenOut.
     */
    function _getAdapterArgs(address tokenIn, address tokenOut)
        internal
        view
        virtual
        returns (bytes[] memory adapterArgs);

    /// @inheritdoc IDexAdapter
    function getMaxOutput(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 maxOutput, bytes memory extraArgs)
    {
        if (tokenIn == tokenOut || amountIn == 0) return (0, new bytes(0));
        (maxOutput, extraArgs) = _getMaxOutput(tokenIn, tokenOut, amountIn);
    }

    /// @inheritdoc IDexAdapter
    function getOutputFromArgs(address tokenIn, address tokenOut, uint256 amountIn, bytes memory extraArgs)
        external
        view
        returns (uint256 amountOut)
    {
        if (tokenIn == tokenOut || amountIn == 0) return 0;
        amountOut = _getOutputFromArgs(tokenIn, tokenOut, amountIn, extraArgs);
    }

    /// @inheritdoc IDexAdapter
    function getAdapterArgs(address tokenIn, address tokenOut) external view returns (bytes[] memory extraArgs) {
        if (tokenIn == tokenOut) return extraArgs;
        extraArgs = _getAdapterArgs(tokenIn, tokenOut);
    }
}
