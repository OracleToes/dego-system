pragma solidity ^0.5.5;
pragma experimental ABIEncoderV2;

import "../interface/IERC20.sol";
import "../library/SafeERC20.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interface/IGegoToken.sol";
import "../interface/IGegoFactoryV2.sol";
import "../interface/IGegoRuleProxy.sol";
import "../library/Governance.sol";

contract GegoFactoryV2 is Governance, IGegoFactoryV2 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;


    event GegoAdded(
        uint256 indexed id,
        uint256 grade,
        uint256 quality,
        uint256 amount,
        uint256 resBaseId,
        uint256 tLevel,
        uint256 ruleId,
        uint256 nftType,
        address author,
        address erc20,
        uint256 createdTime,
        uint256 blockNum
    );

    event GegoBurn(
        uint256 indexed id,
        uint256 amount,
        address erc20
    );

    struct MintData{
        uint256 amount;
        uint256 resBaseId;
        uint256 nftType;
        uint256 ruleId;
        uint256 tLevel;
    }

    struct MintExtraData {
        uint256 gego_id;
        uint256 grade;
        uint256 quality;
        address author;
    }

    event NFTReceived(address operator, address from, uint256 tokenId, bytes data);

    // for minters
    mapping(address => bool) public _minters;

    mapping(uint256 => IGegoToken.Gego) public _gegoes;

    mapping(uint256 => IGegoRuleProxy) public _ruleProxys;

    mapping(address => bool) public _ruleProxyFlags;

    uint256 public _maxGegoV1Id = 1000000;
    uint256 public _gegoId = _maxGegoV1Id;


    IGegoToken public _gegoToken = IGegoToken(0x0);

    bool public _isUserStart = false;

    constructor(address gegoToken) public {
        _gegoToken = IGegoToken(gegoToken);
    }

    function setUserStart(bool start) public onlyGovernance {
        _isUserStart = start;
    }

    function addMinter(address minter) public onlyGovernance {
        _minters[minter] = true;
    }

    function removeMinter(address minter) public onlyGovernance {
        _minters[minter] = false;
    }


    // only function for creating additional rewards from dust
    function seize(IERC20 asset, address teamWallet) public onlyGovernance {
        uint256 balance = asset.balanceOf(address(this));
        asset.safeTransfer(teamWallet, balance);
    }
    

    /**
     * @dev add gego mint strategy address
     * can't remove
     */
    function addGegoRuleProxy(uint256 nftType, address ruleProxy)  public  
    onlyGovernance{
        require(_ruleProxys[nftType] == IGegoRuleProxy(0x0), "must null");

        _ruleProxys[nftType] = IGegoRuleProxy(ruleProxy);

        _ruleProxyFlags[ruleProxy] = true;
    }

    function isRulerProxyContract(address proxy) external view returns ( bool ){
        return _ruleProxyFlags[proxy];
    }

    /*
     * @dev set gego contract address
     */
    function setGegoContract(address gego)  public  
        onlyGovernance{
        _gegoToken = IGegoToken(gego);
    }

    function setCurrentGegoId(uint256 id)  public  
        onlyGovernance{
        _gegoId = id;
    }

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'GegoFactoryV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getGego(uint256 tokenId)
        external view
        returns (
            uint256 grade,
            uint256 quality,
            uint256 amount,
            uint256 resBaseId,
            uint256 tLevel,
            uint256 ruleId,
            uint256 nftType,
            address author,
            address erc20,
            uint256 createdTime,
            uint256 blockNum
        )
    {
        IGegoToken.Gego storage gego = _gegoes[tokenId];
        require(gego.id > 0, "gego not exist");
        grade = gego.grade;
        quality = gego.quality;
        amount = gego.amount;
        resBaseId = gego.resBaseId;
        tLevel = gego.tLevel;
        ruleId = gego.ruleId;
        nftType = gego.nftType;
        author = gego.author;
        erc20 = gego.erc20;
        createdTime = gego.createdTime;
        blockNum = gego.blockNum;
    }

    function getGegoStruct(uint256 tokenId)
        external view
        returns (IGegoToken.Gego memory gego){
            require(_gegoes[tokenId].id > 0, "gego  not exist");
            gego=_gegoes[tokenId];
        }


    function setBaseResId(uint256 tokenId, uint256 resBaseId) external onlyGovernance {
        require( _gegoes[tokenId].id > 0, "gego not exist");
        _gegoes[tokenId].resBaseId = resBaseId;
    }

    function mint(MintData memory mintData, IGegoRuleProxy.Cost721Asset memory costSet1, IGegoRuleProxy.Cost721Asset memory costSet2 ) public 
        lock
    {

        address origin = msg.sender;

        if(_minters[msg.sender] == false){
            require(!origin.isContract(), "call to non-contract");
        }

        require(_isUserStart || _minters[msg.sender]  , "can't mint" );

        require( _ruleProxys[mintData.nftType] != IGegoRuleProxy(0x0), " invalid mint nftType !" );

        uint256 mintAmount;
        address mintErc20;

        IGegoRuleProxy.MintParams memory params;
        params.user = msg.sender;
        params.amount = mintData.amount;
        params.ruleId = mintData.ruleId;

        (mintAmount,mintErc20) = _ruleProxys[mintData.nftType].cost( params,costSet1,costSet2 );

        IGegoToken.Gego memory gego = _ruleProxys[mintData.nftType].generate( msg.sender, mintData.ruleId );

        uint256 gegoId = gego.id;
        if(gegoId  == 0){
            _gegoId++ ;
            gegoId = _gegoId;
        }
        gego.id = gegoId;
        gego.blockNum = gego.blockNum > 0 ? gego.blockNum:block.number;
        gego.createdTime =  gego.createdTime > 0?gego.createdTime:block.timestamp ;

        gego.amount = gego.amount>0?gego.amount:mintAmount;
        gego.resBaseId = gego.resBaseId>0?gego.resBaseId:mintData.resBaseId;
        gego.tLevel = gego.tLevel>0?gego.tLevel:mintData.tLevel;
        gego.erc20 = gego.erc20==address(0x0)?mintErc20:gego.erc20;

        gego.ruleId = mintData.ruleId;
        gego.nftType = mintData.nftType;
        gego.author = gego.author==address(0x0)?msg.sender:gego.author;

        _gegoes[gegoId] = gego;

        _gegoToken.mint(msg.sender, gegoId);

        emit GegoAdded(
            gego.id,
            gego.grade,
            gego.quality,
            gego.amount,
            gego.resBaseId,
            gego.tLevel,
            gego.ruleId,
            gego.nftType,
            gego.author,
            gego.erc20,
            gego.createdTime,
            gego.blockNum
        );

    } 


    function gmMint(MintData memory mintData, MintExtraData memory extraData) public {
        require(_minters[msg.sender]  , "can't mint");

        IGegoRuleProxy.Cost721Asset memory costSet1;
        IGegoRuleProxy.Cost721Asset memory costSet2;

        IGegoRuleProxy.MintParams memory params;
        params.user = msg.sender;
        params.amount = mintData.amount;
        params.ruleId = mintData.ruleId;

        uint256 mintAmount;
        address mintErc20;

        (mintAmount,mintErc20) = _ruleProxys[mintData.nftType].cost( params,costSet1,costSet2 );
      
        uint256 gegoId = extraData.gego_id;
        if(extraData.gego_id == 0){
            _gegoId++ ;
            gegoId = _gegoId;
        }else{
            if(gegoId > _gegoId){
                _gegoId =  gegoId;
            }
        }

        IGegoToken.Gego memory gego;
        gego.id = gegoId;
        gego.blockNum = block.number;
        gego.createdTime =  block.timestamp ;
        gego.grade = extraData.grade;
        gego.quality = extraData.quality;
        gego.amount = mintAmount;
        gego.resBaseId = mintData.resBaseId;
        gego.tLevel = mintData.tLevel;
        gego.ruleId = mintData.ruleId;
        gego.nftType = mintData.nftType;
        gego.author = extraData.author;
        gego.erc20 = mintErc20;

        _gegoes[gegoId] = gego;

        _gegoToken.mint(extraData.author, gegoId);

        emit GegoAdded(
            gego.id,
            gego.grade,
            gego.quality,
            gego.amount,
            gego.resBaseId,
            gego.tLevel,
            gego.ruleId,
            gego.nftType,
            gego.author,
            gego.erc20,
            gego.createdTime,
            gego.blockNum
        );
    } 


    function burn(uint256 tokenId) external returns ( bool ) {
      
        IGegoToken.Gego memory gego = _gegoes[tokenId];
        require(gego.id > 0, "not exist");

        _gegoToken.safeTransferFrom(msg.sender, address(this), tokenId);
        _gegoToken.burn(tokenId);

        emit GegoBurn(gego.id, gego.amount, gego.erc20);

        _ruleProxys[gego.nftType].destroy( msg.sender, gego );

        _gegoes[tokenId].id = 0;

        return true;
    }

    
    function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data) public returns (bytes4) {
        //only receive the _nft staff
        if(address(this) != operator) {
            //invalid from nft
            return 0;
        }
        //success
        emit NFTReceived(operator, from, tokenId, data);
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}
