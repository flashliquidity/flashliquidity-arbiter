// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;
pragma abicoder v2;

interface IAlgebraQuoter {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInput(
        bytes memory path,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    function quoteExactInputSingle(
        QuoteExactInputSingleParams memory params
    ) external view returns (uint256 amountOut);
}
