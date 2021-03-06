pragma solidity ^0.8.0;

import "./Math.sol";
import "./ERC20.sol";

interface IERC20{
    function balanceOf(address) external  returns(uint256);
    function transfer(address to, uint256 amount)  external;
}

error InsufficientLiquidityMinted();
error InsufficientLiquidityBurned();
error TransferFailed();

contract UniswapV2Pair is Math, ERC20{
    uint256 constant MINIMUM_LIQUIDITY = 1000 ;

    address public token0; 
    address public token1;

    uint256 private reserve0; 
    uint256 private reserve1;

    event Burn(address indexed sender, uint256 amount0, uint256 amount1);
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Sync(uint256 reserve0, uint256 reserve1);

    constructor(address _token0, address _token1)
    ERC20("UniswapV2 Pair", "UNIV2", 18){
        token0 =_token0;
        token1 = _token1;
    }

    function mint() public{
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0; 
        uint256 amount1 = balance1 - reserve1;

        uint256 liquidity; 
        if (totalSupply == 0){
            liquidity = Math.sqrt(amount0 * amount1)-MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        }else{
            liquidity = Math.min(
                (amount0 * totalSupply)/_reserve0,
                (amount1 * totalSupply)/_reserve1,
            );
        }

        if (liquidity < 0){
            revert InsufficientLiquidityMinted();
        }

        _mint(msg.sender, liquidity);
        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function getReserves() public view returns(uint112, uint112, uint32) {
        return (reserve0, reserve1, 0);
    }

    function burn()()public {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 liquidity = balanceOf(msg.sender)
        
        uint256 amount0 = (liquidity * balance0) / totalSupply;
        uint256 amount1 = (liquidity * balance1) / totalSupply;

        if(amount0 <= 0 || amount1 <= 0){
            revert InsufficientLiquidityBurned();
        }
        _burn(msg.sender, liquidity);

        _safeTransfer(token0, msg.sender, amount0);
        _safeTransfer(token1, msg.sender, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
    }

}