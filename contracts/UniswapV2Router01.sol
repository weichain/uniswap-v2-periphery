pragma solidity =0.5.4;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';

import './libraries/TransferHelper.sol';
import './libraries/UniswapV2Library.sol';
import './interfaces/IUniswapV2Router01.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

contract UniswapV2Router01 is IUniswapV2Router01 {
    address public factory;
    address public WHYDRA;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'HydraswapRouter: EXPIRED');
        _;
    }

    function() external payable {
        assert(msg.sender == WHYDRA); // only accept HYDRA via fallback from the WHYDRA contract
    }

    constructor(address _factory, address _WHYDRA) public {
        factory = _factory;
        WHYDRA = _WHYDRA;
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) private returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'HydraswapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'HydraswapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }
    function addLiquidityHYDRA(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountHYDRAMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountHYDRA, uint liquidity) {
        (amountToken, amountHYDRA) = _addLiquidity(
            token,
            WHYDRA,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountHYDRAMin
        );
        address pair = UniswapV2Library.pairFor(factory, token, WHYDRA);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);

        address(IWETH(WHYDRA)).call.value(amountHYDRA)(abi.encode("deposit()"));

        assert(IWETH(WHYDRA).transfer(pair, amountHYDRA));
        liquidity = IUniswapV2Pair(pair).mint(to);
        if (msg.value > amountHYDRA) TransferHelper.safeTransferHYDRA(msg.sender, msg.value - amountHYDRA); // refund dust HYDRA, if any
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'HydraswapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'HydraswapRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityHYDRA(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountHYDRAMin,
        address to,
        uint deadline
    ) public ensure(deadline) returns (uint amountToken, uint amountHYDRA) {
        (amountToken, amountHYDRA) = removeLiquidity(
            token,
            WHYDRA,
            liquidity,
            amountTokenMin,
            amountHYDRAMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WHYDRA).withdraw(amountHYDRA);
        TransferHelper.safeTransferHYDRA(to, amountHYDRA);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) private {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = UniswapV2Library.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'HydraswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'HydraswapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }
    function swapExactHYDRAForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WHYDRA, 'HydraswapRouter: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'HydraswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        address(IWETH(WHYDRA)).call.value(amounts[0])(abi.encode("deposit()"));
        assert(IWETH(WHYDRA).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactHYDRA(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WHYDRA, 'HydraswapRouter: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'HydraswapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWETH(WHYDRA).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferHYDRA(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForHYDRA(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WHYDRA, 'HydraswapRouter: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'HydraswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IWETH(WHYDRA).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferHYDRA(to, amounts[amounts.length - 1]);
    }
    function swapHYDRAForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WHYDRA, 'HydraswapRouter: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'HydraswapRouter: EXCESSIVE_INPUT_AMOUNT');
        address(IWETH(WHYDRA)).call.value(amounts[0])(abi.encode("deposit()"));
        assert(IWETH(WHYDRA).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        if (msg.value > amounts[0]) TransferHelper.safeTransferHYDRA(msg.sender, msg.value - amounts[0]); // refund dust HYDRA, if any
    }

    function quote(uint amountA, uint reserveA, uint reserveB) public pure returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public pure returns (uint amountOut) {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public pure returns (uint amountIn) {
        return UniswapV2Library.getAmountOut(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path) public view returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
