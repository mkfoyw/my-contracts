import "./../utils/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/dev/VRFCoordinatorV2.sol";
import "./../utils/IPFSConvert.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// File: contracts/ZombieClubToken.sol

pragma solidity ^0.8.0;

error InvalidTotalMysteryBoxes();
error ReachedMaxSupply();
error TransactionExpired();
error SignatureAlreadyUsed();
error ExceedMaxAllowedMintAmount();
error IncorrectSignature();
error InsufficientPayments();
error RevealNotAllowed();
error MerkleTreeRootNotSet();
error InvalidMerkleTreeProof();
error RequestRevealNotOwner();
error RevealAlreadyRequested();
error IncorrectRevealIndex();
error TokenAlreadyRevealed();
error MerkleTreeProofFailed();
error IncorrectRevealManyLength();
error TokenRevealQueryForNonexistentToken();

/// @title ZombieClubToken
/// @author Teahouse Finance
contract ZombieClubToken is
    ERC721A,
    Ownable,
    ReentrancyGuard,
    VRFConsumerBaseV2
{
    using Strings for uint256;
    using ECDSA for bytes32;

    struct ChainlinkParams {
        bytes32 keyHash;
        uint64 subId;
        uint32 gasLimit;
        uint16 requestConfirms;
    }

    struct TokenReveal {
        bool requested; // token reveal requested
        uint64 revealId;
    }

    struct TokenInternalInfo {
        bool requested; // token reveal requested
        uint64 revealId;
        uint64 lastTransferTime;
        uint64 stateChangePeriod;
    }

    // Chainlink info
    VRFCoordinatorV2Interface public immutable COORDINATOR;
    ChainlinkParams public chainlinkParams;

    address private signer;
    uint256 public price = 0.666 ether;
    uint256 public maxCollection;
    uint64 public presaleEndTime;

    string public unrevealURI;
    bool public allowReveal = false;
    bytes32 public hashMerkleRoot;
    uint256 public revealedTokens;
    uint256 public totalMysteryBoxes;

    // state change period (second)
    uint256 constant stateChangePeriod = 2397600;
    uint256 constant stateChangeVariation = 237600;
    uint256 constant numOfStates = 4;

    mapping(uint256 => uint256) private tokenIdMap;
    mapping(uint256 => bytes32[numOfStates]) private tokenBaseURIHashes;
    mapping(uint256 => uint256) public chainlinkTokenId;
    mapping(uint256 => TokenInternalInfo) private tokenInternalInfo;
    mapping(bytes32 => bool) public signatureUsed;

    event RevealRequested(uint256 indexed tokenId, uint256 requestId);
    event RevealReceived(uint256 indexed tokenId, uint256 revealId);
    event Revealed(uint256 indexed tokenId);

    constructor(
        string memory _name,
        string memory _symbol,
        address _initSigner, // whitelist signer address
        uint256 _maxCollection, // total supply
        uint256 _totalMysteryBoxes, // number of all mystery boxes available
        address _vrfCoordinator, // Chainlink VRF coordinator address
        ChainlinkParams memory _chainlinkParams
    ) ERC721A(_name, _symbol) VRFConsumerBaseV2(_vrfCoordinator) {
        if (_totalMysteryBoxes < _maxCollection)
            revert InvalidTotalMysteryBoxes();

        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        signer = _initSigner;
        maxCollection = _maxCollection;
        totalMysteryBoxes = _totalMysteryBoxes;
        chainlinkParams = _chainlinkParams;
    }

    function setPresaleEndTime(uint64 _newTime) external onlyOwner {
        presaleEndTime = _newTime;
    }

    function setPrice(uint256 _newPrice) external onlyOwner {
        price = _newPrice;
    }

    function setSigner(address _newSigner) external onlyOwner {
        signer = _newSigner;
    }

    function setChainlinkParams(ChainlinkParams memory _chainlinkParams)
        external
        onlyOwner
    {
        chainlinkParams = _chainlinkParams;
    }

    function setUnrevealURI(string calldata _newURI) external onlyOwner {
        unrevealURI = _newURI;
    }

    function setMerkleRoot(bytes32 _hashMerkleRoot) public onlyOwner {
        require(revealedTokens == 0); // can't be changed after someone requested reveal
        hashMerkleRoot = _hashMerkleRoot;
    }

    function setAllowReveal(bool _allowReveal) external onlyOwner {
        allowReveal = _allowReveal;
    }

    function withdraw(address payable _to) external payable onlyOwner {
        (bool success, ) = _to.call{value: address(this).balance}("");
        require(success);
    }

    function isAuthorized(
        address _sender,
        uint32 _allowAmount,
        uint64 _expireTime,
        bytes memory _signature
    ) private view returns (bool) {
        bytes32 hashMsg = keccak256(
            abi.encodePacked(_sender, _allowAmount, _expireTime)
        );
        bytes32 ethHashMessage = hashMsg.toEthSignedMessageHash();

        return ethHashMessage.recover(_signature) == signer;
    }

    function mint(
        uint32 _amount,
        uint32 _allowAmount,
        uint64 _expireTime,
        bytes calldata _signature
    ) external payable {
        if (totalSupply() + _amount > maxCollection) revert ReachedMaxSupply();
        if (block.timestamp > _expireTime) revert TransactionExpired();

        if (block.timestamp > presaleEndTime) {
            // PUBLIC SALE mode
            // does not limit how many tokens one can mint in total,
            // only limit how many tokens one can mint in one go
            // also, make sure one signature can only be used once
            if (_amount > _allowAmount) revert ExceedMaxAllowedMintAmount();

            bytes32 sigHash = keccak256(abi.encodePacked(_signature));
            if (signatureUsed[sigHash]) revert SignatureAlreadyUsed();
            signatureUsed[sigHash] = true;
        } else {
            // WHITELIST SALE mode
            // limit how many tokens one can mint in total
            if (_numberMinted(msg.sender) + _amount > _allowAmount)
                revert ExceedMaxAllowedMintAmount();
        }

        if (!isAuthorized(msg.sender, _allowAmount, _expireTime, _signature))
            revert IncorrectSignature();

        uint256 finalPrice = price * _amount;
        if (msg.value < finalPrice) revert InsufficientPayments();

        _safeMint(msg.sender, _amount);
    }

    function devMint(uint256 _amount, address _to) external onlyOwner {
        if (totalSupply() + _amount > maxCollection) revert ReachedMaxSupply();

        _safeMint(_to, _amount);
    }

    function requestReveal(uint256 _tokenId) external nonReentrant {
        if (!allowReveal) revert RevealNotAllowed();
        if (ownerOf(_tokenId) != msg.sender) revert RequestRevealNotOwner();
        if (tokenInternalInfo[_tokenId].requested)
            revert RevealAlreadyRequested();
        if (hashMerkleRoot == bytes32(0)) revert MerkleTreeRootNotSet();

        uint256 requestId = COORDINATOR.requestRandomWords(
            chainlinkParams.keyHash,
            chainlinkParams.subId,
            chainlinkParams.requestConfirms,
            chainlinkParams.gasLimit,
            1
        );

        tokenInternalInfo[_tokenId].requested = true;
        chainlinkTokenId[requestId] = _tokenId;

        emit RevealRequested(_tokenId, requestId);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
        internal
        override
    {
        uint256 tokenId = chainlinkTokenId[requestId];
        if (
            tokenInternalInfo[tokenId].requested &&
            tokenInternalInfo[tokenId].revealId == 0
        ) {
            uint256 randomIndex = (randomWords[0] %
                (totalMysteryBoxes - revealedTokens)) + revealedTokens;
            uint256 revealId = _tokenIdMap(randomIndex);
            uint256 currentId = _tokenIdMap(revealedTokens);

            tokenIdMap[randomIndex] = currentId;
            tokenInternalInfo[tokenId].revealId = uint64(revealId);
            revealedTokens++;

            emit RevealReceived(tokenId, revealId);
        }
    }

    function reveal(
        uint256 _tokenId,
        bytes32[numOfStates] memory _tokenBaseURIHashes,
        uint256 _index,
        bytes32 _salt,
        bytes32[] memory _proof
    ) public {
        if (hashMerkleRoot == bytes32(0)) revert MerkleTreeRootNotSet();
        if (_index == 0 || tokenInternalInfo[_tokenId].revealId != _index)
            revert IncorrectRevealIndex();
        if (tokenBaseURIHashes[_tokenId][0] != 0) revert TokenAlreadyRevealed();

        // perform merkle root proof verification
        bytes32 hash = keccak256(
            abi.encodePacked(_tokenBaseURIHashes, _index, _salt)
        );
        if (!MerkleProof.verify(_proof, hashMerkleRoot, hash))
            revert MerkleTreeProofFailed();

        tokenBaseURIHashes[_tokenId] = _tokenBaseURIHashes;
        _setTokenTimeInfo(_tokenId);

        emit Revealed(_tokenId);
    }

    function revealMany(
        uint256[] memory _tokenIds,
        bytes32[numOfStates][] memory _tokenBaseURIHashes,
        uint256[] memory _indexes,
        bytes32[] memory _salts,
        bytes32[][] memory _prooves
    ) public {
        if (hashMerkleRoot == bytes32(0)) revert MerkleTreeRootNotSet();
        if (_tokenIds.length != _tokenBaseURIHashes.length)
            revert IncorrectRevealManyLength();
        if (_tokenIds.length != _indexes.length)
            revert IncorrectRevealManyLength();
        if (_tokenIds.length != _salts.length)
            revert IncorrectRevealManyLength();
        if (_tokenIds.length != _prooves.length)
            revert IncorrectRevealManyLength();

        uint256 i;
        uint256 length = _tokenIds.length;
        for (i = 0; i < length; i++) {
            if (tokenBaseURIHashes[_tokenIds[i]][0] == 0) {
                // only calls reveal for those not revealed yet
                // this is to revent the case where one revealed token will cause the entire batch to revert
                // we only check for "revealed" but not for other situation as the entire batch is supposed to have
                // correct parameters
                reveal(
                    _tokenIds[i],
                    _tokenBaseURIHashes[i],
                    _indexes[i],
                    _salts[i],
                    _prooves[i]
                );
            }
        }
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        if (!_exists(_tokenId)) revert URIQueryForNonexistentToken();

        if (tokenBaseURIHashes[_tokenId][0] == 0) {
            return unrevealURI;
        } else {
            bytes32 hash = tokenBaseURIHashes[_tokenId][
                _getZombieState(_tokenId)
            ];
            return
                string(
                    abi.encodePacked(
                        "ipfs://",
                        IPFSConvert.cidv0FromBytes32(hash)
                    )
                );
        }
    }

    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }

    function numberMinted(address _minter) external view returns (uint256) {
        return _numberMinted(_minter);
    }

    function tokenReveal(uint256 _tokenId)
        external
        view
        returns (TokenReveal memory)
    {
        if (!_exists(_tokenId)) revert TokenRevealQueryForNonexistentToken();

        return
            TokenReveal({
                requested: tokenInternalInfo[_tokenId].requested,
                revealId: tokenInternalInfo[_tokenId].revealId
            });
    }

    function ownedTokens(
        address _addr,
        uint256 _startId,
        uint256 _endId
    ) external view returns (uint256[] memory, uint256) {
        if (_endId == 0) {
            _endId = _currentIndex - 1;
        }

        if (_startId < _startTokenId() || _endId >= _currentIndex)
            revert TokenIndexOutOfBounds();

        uint256 i;
        uint256 balance = balanceOf(_addr);
        if (balance == 0) {
            return (new uint256[](0), _endId + 1);
        }

        if (balance > 256) {
            balance = 256;
        }

        uint256[] memory results = new uint256[](balance);
        uint256 idx = 0;

        address owner = ownerOf(_startId);
        for (i = _startId; i <= _endId; i++) {
            if (_ownerships[i].addr != address(0)) {
                owner = _ownerships[i].addr;
            }

            if (!_ownerships[i].burned && owner == _addr) {
                results[idx] = i;
                idx++;

                if (idx == balance) {
                    if (balance == balanceOf(_addr)) {
                        return (results, _endId + 1);
                    } else {
                        return (results, i + 1);
                    }
                }
            }
        }

        uint256[] memory partialResults = new uint256[](idx);
        for (i = 0; i < idx; i++) {
            partialResults[i] = results[i];
        }

        return (partialResults, _endId + 1);
    }

    function unrevealedTokens(uint256 _startId, uint256 _endId)
        external
        view
        returns (uint256[] memory, uint256)
    {
        if (_endId == 0) {
            _endId = _currentIndex - 1;
        }

        if (_startId < _startTokenId() || _endId >= _currentIndex)
            revert TokenIndexOutOfBounds();

        uint256 i;
        uint256[] memory results = new uint256[](256);
        uint256 idx = 0;

        for (i = _startId; i <= _endId; i++) {
            if (
                tokenInternalInfo[i].revealId != 0 &&
                tokenBaseURIHashes[i][0] == 0
            ) {
                // reveal received but not revealed
                results[idx] = i;
                idx++;

                if (idx == 256) {
                    return (results, i + 1);
                }
            }
        }

        uint256[] memory partialResults = new uint256[](idx);
        for (i = 0; i < idx; i++) {
            partialResults[i] = results[i];
        }

        return (partialResults, _endId + 1);
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _tokenIdMap(uint256 _index) private view returns (uint256) {
        if (tokenIdMap[_index] == 0) {
            return _index + 1;
        } else {
            return tokenIdMap[_index];
        }
    }

    function _getZombieState(uint256 _tokenId) internal view returns (uint256) {
        uint256 duration = block.timestamp -
            tokenInternalInfo[_tokenId].lastTransferTime;
        uint256 state = duration /
            tokenInternalInfo[_tokenId].stateChangePeriod;
        if (state >= numOfStates) {
            state = numOfStates - 1;
        }

        while (tokenBaseURIHashes[_tokenId][state] == 0) {
            state--;
        }

        return state;
    }

    function _afterTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 /*quantity*/
    ) internal override {
        // only reset token time info when actually transfering the token
        // not when minting
        // so "quantity" should always be 1
        if (from != address(0) && to != address(0)) {
            _setTokenTimeInfo(startTokenId);
        }
    }

    function _setTokenTimeInfo(uint256 _tokenId) private {
        tokenInternalInfo[_tokenId].lastTransferTime = uint64(block.timestamp);
        tokenInternalInfo[_tokenId].stateChangePeriod = uint64(
            stateChangePeriod + (_randomNumber() % stateChangeVariation)
        );
    }

    function _randomNumber() internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        blockhash(block.number - 1),
                        block.timestamp
                    )
                )
            );
    }
}
