// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IDexAdapter
 * @author Oddcod3 (@oddcod3)
 */
interface IDexAdapter {
    /**
     * @dev Executes a token swap in the specified pool using this adapter.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param to The recipient of the swap.
     * @param amountIn The amount of input tokens to be swapped.
     * @param amountOutMin The minimum amount out of output tokens below which the swap reverts.
     * @param extraArgs Adapter specific encoded extra arguments, used for providing additional instructions or data required by the specific DEX adapter.
     * @return amountOut The amount of output token received.
     */
    function swap(
        address tokenIn,
        address tokenOut,
        address to,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes memory extraArgs
    ) external returns (uint256 amountOut);

    /**
     * @dev Identifies the optimal target pool that maximizes the amount of output tokens received.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of input tokens to be swapped.
     * @return maxOutput The maximum amount of output tokens that can be received.
     * @return extraArgs Adapter specific encoded extra arguments, used for providing additional instructions or data required by the specific DEX adapter.
     * @notice This function scans available pools to find the one that provides the highest return for the given input token and amount.
     */
    function getMaxOutput(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 maxOutput, bytes memory extraArgs);

    /**
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of input tokens to be swapped.
     * @param extraArgs Adapter specific encoded extra arguments, used for providing additional instructions or data required by the specific DEX adapter.
     * @return amountOut The amount of output tokens received.
     */
    function getOutputFromArgs(address tokenIn, address tokenOut, uint256 amountIn, bytes memory extraArgs)
        external
        view
        returns (uint256 amountOut);

    /**
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @return adapterArgs Array of adapter extraArgs given the tokenIn and tokenOut.
     *
     */
    function getAdapterArgs(address tokenIn, address tokenOut) external view returns (bytes[] memory adapterArgs);

    /**
     * @return description A string containing the description and version of the adapter.
     * @notice This function returns a textual description and version number of the adapter,
     */
    function s_description() external view returns (string memory description);
}
