pragma solidity =0.5.4;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/Babylonian.sol';

import '../libraries/TransferHelper.sol';
import '../libraries/UniswapV2LiquidityMathLibrary.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IUniswapV2Router01.sol';
import '../libraries/SafeMath.sol';
import '../libraries/UniswapV2Library.sol';

contract ExampleSwapToPrice {
    using SafeMath for uint256;

    IUniswapV2Router01 public router;
    address public factory;

    constructor(address factory_, IUniswapV2Router01 router_) public {
        factory = factory_;
        router = router_;
    }

    function swapToPrice(
        address tokenA,
        address tokenB,
        uint256 tokenAAmountIn,
        uint256 tokenBMinOut,
        address to,
        uint256 deadline
    ) public {
        require(tokenAAmountIn != 0 , "ExampleSwapToPrice: TOKEN_A - ZERO_AMOUNT");
        require(tokenBMinOut != 0, "ExampleSwapToPrice: TOKEN_B - ZERO_AMOUNT_MIN");
        
        TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), tokenAAmountIn);
        TransferHelper.safeApprove(tokenA, address(router), tokenAAmountIn);

        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;

        router.swapExactTokensForTokens(
            tokenAAmountIn,
            tokenBMinOut,
            path,
            to,
            deadline
        );
    }
}