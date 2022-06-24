pragma solidity ^0.8.2;

import "./../utils/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract goblintownNFT is ERC721A, Ownable, ReentrancyGuard {
    using Strings for uint256;
    string public _partslink;
    bool public byebye = false;
    uint256 public goblins = 9999;
    uint256 public goblinbyebye = 1;
    mapping(address => uint256) public howmanygobblins;

    constructor() ERC721A("goblintown", "GOBLIN") {}

    function _baseURI() internal view virtual override returns (string memory) {
        return _partslink;
    }

    function makingobblin() external nonReentrant {
        uint256 totalgobnlinsss = totalSupply();
        require(byebye);
        require(totalgobnlinsss + goblinbyebye <= goblins);
        require(msg.sender == tx.origin);
        require(howmanygobblins[msg.sender] < goblinbyebye);
        _safeMint(msg.sender, goblinbyebye);
        howmanygobblins[msg.sender] += goblinbyebye;
    }

    function makegoblinnnfly(address lords, uint256 _goblins) public onlyOwner {
        uint256 totalgobnlinsss = totalSupply();
        require(totalgobnlinsss + _goblins <= goblins);
        _safeMint(lords, _goblins);
    }

    function makegoblngobyebye(bool _bye) external onlyOwner {
        byebye = _bye;
    }

    function spredgobblins(uint256 _byebye) external onlyOwner {
        goblinbyebye = _byebye;
    }

    function makegobblinhaveparts(string memory parts) external onlyOwner {
        _partslink = parts;
    }

    function sumthinboutfunds() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success);
    }
}
