pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IExchange{
    function ethToTokenSwap(uint256 _mintTokens) external payable;
    function ethToTokenTransfer(uint256 _mintTokens, address _receipt)external payable;
}

interface IFactory{
    function getExhange(address _tokenAddress) external returns(address);
}


contract Exchange is ERC20{
    address public tokenAddress;
    address public factoryAddress;

    constructor(address _token)ERC20("Uniswap-V1", "UNI-V1"){
        require(_token != address(0), "invalid token address");
        tokenAddress = _token ;
        factoryAddress = msg.sender;
    }

    function getReserve() public view returns(uint256){
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    function addLiquidity(uint256 _tokenAmount)external payable returns(uint256){
        // 添加初始流动性
        if (getReserve() == 0){
            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), _tokenAmount);

            uint256 liquidity = address(this).balance;
            _mint(msg.sender, liquidity);
        }else{
        // 提供流动性
            uint256 tokenReserve = getReserve();
            uint256 ethReserve = address(this).balance;
            uint256 tokenAmount = (msg.value*tokenReserve)/ethReserve; 
            require(_tokenAmount > tokenAmount, "insufficient token amount");

            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), tokenAmount);
            
            uint256 liquidity = (msg.value * totalSupply())/ethReserve;
            _mint(msg.sender, liquidity);
        }
    }

    function removeLiquidity(uint256 _amount) public returns(uint256, uint256){
        require(_amount > 0, "invalid amount");

       uint256 ethAmount = (_amount * address(this).balance)/totalSupply();
       uint256 tokenAmount = (_amount * getReserve())/totalSupply();

       _burn(msg.sender, _amount);
       payable(msg.sender).transfer(ethAmount);
       IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
       return (ethAmount, tokenAmount);
    }

    function getTokenAmount(uint256 _ethSold)public view returns(uint256){
        require(_ethSold > 0, "ethSold is too small");

        uint256 tokenReserve = getReserve();
        return getAmount(_ethSold, address(this).balance, tokenReserve);
    }

    function getEthAmount(uint256 _tokenSold) public view returns(uint256) {
        require(_tokenSold > 0, "tokenSold is too small"); 
        uint256 tokenReserve = getReserve();
        return getAmount(_tokenSold,tokenReserve,address(this).balance);
    }

    function ethToToken(uint256 _minTokens, address receipt)private{
        uint256 tokenReserve = getReserve();
        uint256 tokenBoughts = getAmount(msg.value, address(this).balance - msg.value, tokenReserve);
        require(tokenBoughts > _minTokens, "insufficent output amount");
        IERC20(tokenAddress).transfer(receipt, tokenBoughts);
    }

    function ethToTokenTransfer(uint256 _minTokens, address _receipt) public payable{
        ethToToken(_minTokens, _receipt);
    }

    function ethToTokenSwap(uint256 _minTokens, address _receipt)public payable{
        ethToToken(_minTokens, _receipt);
    }

    function tokenToEthSwap(uint256 _tokenSold, uint256 _minEth) public{
        uint256 tokenReserve = getReserve();
        uint256 ethBoughts = getAmount(_tokenSold, tokenReserve, address(this).balance);
        require(ethBoughts > _minEth, "sufficient output amount");

        IERC20(tokenAddress).transferFrom(msg.sender, address(this), _tokenSold);
        payable(msg.sender).transfer(ethBoughts);
    }

    function tokenToTokenSwap(uint256 _tokensSold, uint256 _minTokensBought, address _tokenAddress)public{
        address exchangeAddress = IFactory(factoryAddress).getExhange(_tokenAddress);
        require(exchangeAddress != address(0), "invalid exchange address");

        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(_tokensSold, tokenReserve, address(this).balance);

        IERC20(tokenAddress).transferFrom(msg.sender, address(this), _tokensSold);
        IExchange(exchangeAddress).ethToTokenTransfer{value: ethBought}(_minTokensBought, msg.sender);
    }

    function getAmount(uint256 inputAmount, uint256 inputReserve ,uint256 outReserve )public pure returns(uint256){
        require(inputAmount >0 && outReserve >0, "invalid reserves");
        uint256 inputAmountWithFee = inputAmount *99;
        uint256 numberator = outReserve * inputAmountWithFee;
        uint256 denominator = (inputReserve * 100) + inputAmountWithFee;
        return numberator/denominator;
    }
}

