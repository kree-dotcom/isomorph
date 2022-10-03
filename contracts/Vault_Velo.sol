//SPDX-License-Identifier: UNLICENSED 
pragma solidity =0.8.9; 
pragma abicoder v2;

import "./interfaces/IMoUSDToken.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IVault.sol";
import "hardhat/console.sol";

import "./interfaces/ICollateralBook.sol";
import "./interfaces/IDepositReceipt.sol";


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./RoleControl.sol";

uint256 constant VAULT_VELO_TIME_DELAY = 3 days;


contract Vault_Velo is RoleControl(VAULT_VELO_TIME_DELAY), Pausable {

    using SafeERC20 for IERC20;

    //Constants
    uint256 public constant LIQUIDATION_RETURN = 95 ether /100; //95% returned on liquidiation
    uint256 private constant LOWER_LIQUIDATION_BAND = 95 ether /100; //95% used to determine if liquidation is close to needed value
    uint256 private constant LOAN_SCALE = 1 ether; //base for division/decimal maths
    uint256 private constant NOT_OWNED = 999; //used to determine if a user owns an NFT, 
    uint256 private constant NO_NFT_RETURNED = 888;
    //users can only hold 8 NFTS relating to a loan so returning 999 is clearly out of bounds, not owned. 888 is no NFT to return, also out of bounds.
    uint256 private constant NFT_LIMIT = 8; //the number of slots available on each loan for storing NFTs, used as loop bound. 
    uint256 private constant TENTH_OF_CENT = 1 ether /1000; //$0.001

    //structure to store up to 8 NFTids for each loan, if more are required use a different address.
    //could be packed more efficiently probably but we're on optimism so not as important.
    struct NFTids {
        uint256[NFT_LIMIT] ids;
    }

    //structure used to store loan NFT ids and which slots in the array ids they are stored in 
    struct CollateralNFTs{
        uint256[NFT_LIMIT] ids;
        uint256[NFT_LIMIT] slots;
    }

    //these mappings store the loan details of each users loan against each collateral.
    //loan and interest, stored as a virtualPrice adjusted value 
    mapping(address => mapping(address => uint256)) public moUSDLoanAndInterest;
    //loan principle only, not adjusted by virtualPrice
    mapping(address => mapping(address => uint256)) public moUSDLoaned;
    //NFT ids relating to a specific loan
    mapping(address => mapping(address => NFTids)) internal loanNFTids;

    //variables relating to access control and setting new roles
    bytes32 private constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    //Variables 
    //These three control max loans opened per day
    uint256 public dailyMax = 1_000_000 ether; //one million with 18d.p.
    uint256 public dayCounter = block.timestamp;
    uint256 public dailyTotal = 0;

    //These two handle the opening fee paid to the protocol by users 
    uint256 public constant loanOpenFee = 1 ether /100; //1 percent opening fee.


    //Mainnet addresses
    
   

    
    ITreasury public treasury;
    IMoUSDToken public moUSD;
    ICollateralBook public collateralBook;
    

    
    event OpenOrIncreaseLoanNFT(address indexed user, uint256 loanTaken, bytes32 indexed collateralToken, uint256 collateralAmount); 
    event IncreaseCollateralNFT(address indexed user, bytes32 indexed collateralToken, uint256 collateralAmount); 
    event ClosedLoanNFT(address indexed user, uint256 loanAmountReturned, bytes32 indexed collateralToken, uint256 returnedCapitaltoUser);
    event LiquidationNFT(address indexed loanHolder, address indexed Liquidator, uint256 loanAmountReturned, bytes32 indexed collateralToken, uint256 liquidatedCapital);
    event BadDebtClearedNFT(address indexed loanHolder, address indexed Liquidator, uint256 debtCleared, bytes32 indexed collateralToken);
    event ChangeDailyMax(uint256 newDailyMax, uint256 oldDailyMax);

    event SystemPaused(address indexed pausedBy);
    event SystemUnpaused(address indexed unpausedBy);

    /// @notice basic checks to verify collateral being used exists and sanity check for loan holder
    /// @dev should be called by any external function modifying another users loan in some way
    function _validMarketConditions(address _collateralAddress, address _loanHolder) internal view{
        _collateralExists(_collateralAddress);
        require(_loanHolder != address(0), "Zero address used"); 
        //_;
    }
    
    /// @notice stripped down version of validMarketConditions used when checks of loanHolder aren't necessary
    /// @dev should be called by any external function modifying the msg.sender's loan
    function _collateralExists(address _collateralAddress) internal view {
        require(collateralBook.collateralValid(_collateralAddress), "Unsupported collateral!");
        //_;
    }

    modifier onlyPauser{
        bool validUser = hasRole(ADMIN_ROLE, msg.sender) || hasRole(PAUSER_ROLE, msg.sender);
        require(validUser, "Caller is not able to call pause");
        _;
    }
    
    constructor(
        address _moUSD, //moUSD address
        address _treasury, //treasury address
        address _collateralBook //collateral structure book address
        ){
        //cd ("CURRENT BLOCK NUMBER", block.number);
        require(_moUSD != address(0), "Zero Address used MOUSD");
        require(_treasury != address(0), "Zero Address used Treasury");
        require(_collateralBook != address(0), "Zero Address used Collateral");
        moUSD = IMoUSDToken(_moUSD);
        treasury = ITreasury(_treasury);
        collateralBook = ICollateralBook(_collateralBook);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
       
    } 

    /**
        External onlyOwner governance functions
     */


    /// @notice sets state to paused only triggerable by pauser (all admins are pausers also)
    function pause() external onlyPauser {
        _pause();
        emit SystemPaused(msg.sender);
    }
    /// @notice sets state to unpaused only triggerable by admin
    function unpause() external onlyAdmin {
        _unpause();
        emit SystemUnpaused(msg.sender);
    }

    /// @notice dailyMax can be set to 0 effectively preventing anyone from opening new loans.
    function setDailyMax(uint256 _dailyMax) external onlyAdmin {
        require(_dailyMax < 100_000_000 ether ); //sanity check, require less than 100 million opened per day
        emit ChangeDailyMax(_dailyMax, dailyMax);
        dailyMax = _dailyMax;
        
    }

    //function required to receive ERC721s to this contract
    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata data
    ) external returns (bytes4){
        return(IERC721Receiver.onERC721Received.selector);
    }

    /**
        Internal helper and check functions
     */


    /// @notice while this could be abused to DOS the system, given the openLoan fee of 1% this is unlikely
    function _checkDailyMaxLoans(uint256 _amountAdded) internal {
        if (block.timestamp > dayCounter + 1 days ){
            dailyTotal = _amountAdded;
            dayCounter = block.timestamp;
        }
        else{
            dailyTotal += _amountAdded;
        }
        require( dailyTotal  < dailyMax, "Try again tomorrow loan opening limit hit");
    }
    
    function _priceCollateral(IDepositReceipt depositReceipt, uint256 _NFTId) internal view returns(uint256){  
        uint256 pooledTokens = depositReceipt.pooledTokens(_NFTId);      
        return( depositReceipt.priceLiquidity(pooledTokens));
    }

    function _totalCollateralValue(address _collateralAddress, address _owner) internal view returns(uint256){
        NFTids memory userNFTs = loanNFTids[_collateralAddress][_owner];
        IDepositReceipt depositReceipt = IDepositReceipt(_collateralAddress);
        uint256 totalPooledTokens;
        for(uint256 i =0; i < NFT_LIMIT; i++){
            //check if each slot contains an NFT
            if (userNFTs.ids[i] != 0){
                totalPooledTokens += depositReceipt.pooledTokens(userNFTs.ids[i]);
            }
        }
        return(depositReceipt.priceLiquidity(totalPooledTokens));
    }

    /// @param _collateralAddress the address of the collateral token you are fetching
    /// @notice returns all collateral struct fields seperately so that functions requiring 
    /// @notice them can only locally store the ones they need
    function _getCollateral(address _collateralAddress) internal view returns(
        bytes32 ,
        uint256 ,
        uint256 ,
        uint256 ,
        uint256 ,
        uint256 
        ){
        ICollateralBook.Collateral memory collateral = collateralBook.collateralProps(_collateralAddress);
        return (collateral.currencyKey, collateral.minOpeningMargin,
        collateral.liquidatableMargin, collateral.interestPer3Min, collateral.lastUpdateTime, collateral.virtualPrice);
    }


    /// @param _percentToPay the percentage of the total sum express as a fee
    /// @param _amount quantity of which to work out the percentage splits of
    /// @dev internal function used to calculate treasury fees on opening loans
    /// @return postFees is the quantity after the percentToPay has been deducted from it,
    /// @return feeToPay is the percentToPay of original _amount.
    function _findFees(uint256 _percentToPay, uint256 _amount) internal pure returns(uint256, uint256){
        uint256 feeToPay = (_amount * _percentToPay) / LOAN_SCALE;
        uint256 postFees = _amount - feeToPay;
        return (postFees, feeToPay);
    }


    /// @param _currentBlockTime this should always be block.timestamp, passed in by trusted functions
    /// @param _collateralAddress the address of the collateral token you wish to update the virtual price of 
    /// @dev this function should ONLY be called by other vault functions in which they pass in the block timestamp directly to this.
    /// @dev currently uses interest calculations per 3 minutes to save gas and prevent DOS loop situations
    function _updateVirtualPrice(uint256 _currentBlockTime, address _collateralAddress) internal { 
        (   ,
            ,
            ,
            uint256 interestPer3Min,
            uint256 lastUpdateTime,
            uint256 virtualPrice
        ) = _getCollateral(_collateralAddress);
        uint256 timeDelta = _currentBlockTime - lastUpdateTime;
        //exit gracefully if two users call the function for the same collateral in the same block 
        uint256 threeMinuteDelta = timeDelta / 180; 
        if(threeMinuteDelta > 0) {
            for (uint256 i = 0; i < threeMinuteDelta; i++ ){
            virtualPrice = (virtualPrice * interestPer3Min) / LOAN_SCALE; 
            }
            collateralBook.vaultUpdateVirtualPriceAndTime(_collateralAddress, virtualPrice, _currentBlockTime);
        }
    }
    

     /**
      * @notice Only Vaults can mint moUSD.
      * @dev internal function to handle increases of loan
      * @param _loanAmount amount of moUSD to be borrowed, some is used to pay the opening fee the rest is sent to the user.
     **/
    function _increaseLoan(uint256 _loanAmount) internal {
        uint256 userMint;
        uint256 loanFee;
        _checkDailyMaxLoans(_loanAmount);
        (userMint, loanFee) = _findFees(loanOpenFee, _loanAmount);
        moUSD.mint(_loanAmount);
        moUSD.transfer(msg.sender, userMint);
        moUSD.transfer(address(treasury), loanFee);
    }
    /// @dev internal function used to increase user collateral on loan.
    /// @param _depositReceipt the ERC721 compatible collateral to use, already set up in another function
    /// @param _NFTid the unique idenfifier for this specific NFT, ownership already verified 
    function _increaseCollateral(IDepositReceipt _depositReceipt, uint256 _NFTid) internal {
        _depositReceipt.transferFrom(msg.sender, address(this), _NFTid);
    }

    
    /// @dev internal function used to decrease user collateral on loan by sending back an NFT
    /// @param _collateralAddress the Liquidity Certificate ERC721 compatible collateral address 
    /// @param _loanNFTs structure containing the loan's NFT ids and the related slot it is stored in,
    /// @dev  should already be checked and verified before inputting to this function
    /// @param _partialPercentage percentage of the 4th NFT that will be liquidated (0-100%)
    /// @param _USDReturned quantity of moUSD being returned to the vault, this can be zero.
    /// @param _interestPaid quantity of interest paid on closing loan, this is transfered to the treasury, this can be zero
    function _decreaseLoanOrCollateral(
        address _collateralAddress,
        address _loanHolder, 
        CollateralNFTs memory _loanNFTs, 
        uint256 _partialPercentage, 
        uint256 _USDReturned,
        uint256 _interestPaid
        ) internal {
        //only process moUSD if it's non-zero.
        if (_USDReturned != 0){
            //_interestPaid is always less thn _USDReturned so this is safe.
            uint256 USDBurning = _USDReturned - _interestPaid;
            moUSD.transferFrom(msg.sender, address(this), _USDReturned);
            //burn original loan principle
            moUSD.burn(address(this), USDBurning);
            //transfer interest earned on loan to treasury
            moUSD.transfer(address(treasury), _interestPaid);
        }
        _returnAndSplitNFTs(_collateralAddress, _loanHolder, _loanNFTs, _partialPercentage);
        
    }

    function _checkNFTOwnership(address _collateralAddress, uint256 _NFTId, address _owner) internal view returns(uint256){
        require(_NFTId != 0 , "Zero NFTId not allowed");
        NFTids memory userNFTs = loanNFTids[_collateralAddress][_owner];
        for(uint256 i =0; i < NFT_LIMIT; i++){
            //check if each slot matches our specified NFT
            if (userNFTs.ids[i] == _NFTId){
                //if so return the slot so we know
                return (i);
            }
            //only slots 0-7 are valid, so if 999 is returned then we know the user has no loan against this NFT id.
            return (NOT_OWNED);
        }
    }


    /**
        Public functions 
    */


    function getLoanNFTids(address _user, address _collateralAddress, uint256 _index) public view returns(uint256){
        return(loanNFTids[_collateralAddress][_user].ids[_index]);
    }

    /**
        External user loan interaction functions
     */


     /**
      * @notice Only Vaults can mint moUSD.
      * @dev Mints 'USDborrowed' amount of moUSD to vault and transfers to msg.sender and emits transfer event.
      * @param _collateralAddress address of deposit receipt being used as loan collateral.
      * @param _NFTId the NFT id which maps the NFT to it's characteristics
      * @param _USDborrowed amount of moUSD to be minted, it is then split into the amount sent and the opening fee.
     **/
    function openLoan(
        address _collateralAddress,
        uint256 _NFTId,
        uint256 _USDborrowed,
        bool _addingCollateral
        ) external whenNotPaused  
        {   
            _validMarketConditions(_collateralAddress, msg.sender);
            IDepositReceipt depositReceipt;
            uint256 addedValue;
            if(_addingCollateral){
                //zero indexes cause problems with mappings and ownership, so refuse them
                require(_NFTId != 0, "No zero index NFTs allowed");
                depositReceipt = IDepositReceipt(_collateralAddress);
                //checks msg.sender owns specified NFT id
                require(depositReceipt.ownerOf(_NFTId) == msg.sender, "Only NFT owner can openLoan");
                //get the specified certificate details
                addedValue = _priceCollateral(depositReceipt, _NFTId);
            }
        
        
        _updateVirtualPrice(block.timestamp, _collateralAddress);  
        
        (   
            bytes32 currencyKey,
            uint256 minOpeningMargin,
            ,
            ,
            ,
            uint256 virtualPrice
        ) = _getCollateral(_collateralAddress);

        { //scoping to avoid stack too deep
            uint256 existingLoan = moUSDLoanAndInterest[_collateralAddress][msg.sender] * virtualPrice /LOAN_SCALE;
            uint256 borrowMargin = ((_USDborrowed+ existingLoan) * minOpeningMargin) /LOAN_SCALE;
            uint256 existingCollateral = _totalCollateralValue(_collateralAddress, msg.sender); 
            require( addedValue + existingCollateral >= borrowMargin, "Minimum margin not met!");
        }
        if(_addingCollateral){
            _increaseCollateral(depositReceipt, _NFTId);
        }
        
        _increaseLoan(_USDborrowed);

        moUSDLoaned[_collateralAddress][msg.sender] = moUSDLoaned[_collateralAddress][msg.sender] + _USDborrowed;
        moUSDLoanAndInterest[_collateralAddress][msg.sender] = moUSDLoanAndInterest[_collateralAddress][msg.sender] + ((_USDborrowed * LOAN_SCALE) / virtualPrice);
        NFTids storage userNFTs = loanNFTids[_collateralAddress][msg.sender];
        for(uint256 i =0; i < NFT_LIMIT; i++){
            //if this id slot isn't already full assign it
            if (userNFTs.ids[i] == 0){
                userNFTs.ids[i] = _NFTId;
                //then break so only one slot is assigned this id
                break;
            }
            else{
                if(i == NFT_LIMIT -1){
                    //we have reached the final position and there are no free slots
                    revert("All NFT slots for loan used");
                }
            }
        }
        emit OpenOrIncreaseLoanNFT(msg.sender, _USDborrowed, currencyKey, addedValue);
    }


    /**
      * @dev Increases collateral supplied against an existing loan. 
      * @notice Checks adding the collateral will keep the user above liquidation, 
      * @notice this check isn't technically needed but feels fairer to end users.
      * @param _collateralAddress address of collateral token being used.
      * @param _NFTId the NFT id which maps the NFT to it's characteristics
     **/
    function increaseCollateralAmount(
        address _collateralAddress,
        uint256 _NFTId
        ) external whenNotPaused 
        {
        _collateralExists(_collateralAddress);
        //zero indexes cause problems with mappings and ownership, so refuse them
        require(_NFTId != 0, "No zero index NFTs allowed");
        uint256 existingCollateral = _totalCollateralValue(_collateralAddress, msg.sender);
        require( existingCollateral > 0, "No existing collateral!"); //feels like semantic overloading and also problematic for dust after a loan is 'closed'
        //checks msg.sender owns specified NFT id
        IDepositReceipt depositReceipt = IDepositReceipt(_collateralAddress);
        require(depositReceipt.ownerOf(_NFTId) == msg.sender, "Only NFT owner can openLoan");
        //get the specified collateral's value
        uint256 addedValue = _priceCollateral(depositReceipt, _NFTId);
        require( addedValue > 0 , "Zero value added"); //Not strictly needed, prevents event spamming though
        //make sure virtual price is related to current time before fetching collateral details
        _updateVirtualPrice(block.timestamp, _collateralAddress);
        (   
            bytes32 currencyKey,
            ,
            uint256 liquidatableMargin,
            ,
            ,
            uint256 virtualPrice
        ) = _getCollateral(_collateralAddress);
        //We check adding the collateral brings the user above the liquidation point to avoid instantly being liquidated, poor UX 
        uint256 USDborrowed = (moUSDLoanAndInterest[_collateralAddress][msg.sender] * virtualPrice) / LOAN_SCALE;
        uint256 borrowMargin = (USDborrowed * liquidatableMargin) / LOAN_SCALE;
        require(existingCollateral + addedValue >= borrowMargin, "Liquidation margin not met!");
    
        //update mapping with new collateral amount 
        emit IncreaseCollateralNFT(msg.sender, currencyKey, addedValue);
        NFTids storage userNFTs = loanNFTids[_collateralAddress][msg.sender];
        for(uint256 i =0; i < NFT_LIMIT; i++){
            //if this id slot isn't already full assign it
            if (userNFTs.ids[i] == 0){
                userNFTs.ids[i] = _NFTId;
                //then break so only one slot is assigned this id
                break;
            }
            else{
                if(i == NFT_LIMIT -1){
                    //we have reached the final position and there are no free slots
                    revert("All NFT slots for loan used");
                }
            }
        }
        _increaseCollateral(depositReceipt, _NFTId);
        
    }


     /**
      * @notice Only Vaults can destroy moUSD.
      * @dev destroys USDreturned of moUSD held by caller, returns user collateral, close debt 
      * @dev if debt remains, checks minimum collateral ratio is upheld 
      * @dev we ignore debt less than $0.001 this value must be less than the tx cost of a transaction to avoid slowly draining value with microloans
      * @param _collateralAddress address of collateral token being used.
      * @param _loanNFTs structure containing the loan's NFT ids being returned and the related slot it is stored in,
      * @dev don't trust user input for this, always verify the ids match the user given slot before using.
      * @notice the final nftId slot is always used for the partially liquidating NFT (if any are used)
      * @param _USDToVault amount of moUSD to be burnt.
      * @param _partialPercentage percentage of the final NFT that will be liquidated (0-100% in 10^18 scale)
     **/

    
    function closeLoan(
        address _collateralAddress,
        CollateralNFTs memory _loanNFTs,
        uint256 _USDToVault,
        uint256 _partialPercentage
        ) external whenNotPaused 
        {
        _validMarketConditions(_collateralAddress, msg.sender);
        //check input NFT slots and ids are correct
        for(uint256 i = 0; i < NFT_LIMIT; i++){
                require(_loanNFTs.slots[i] == 
                    _checkNFTOwnership(_collateralAddress, _loanNFTs.ids[i], msg.sender),
                     "Incorrect NFT details inputted");
            }
        _updateVirtualPrice(block.timestamp, _collateralAddress);
        (   
            bytes32 currencyKey,
            uint256 minOpeningMargin,
            ,
            ,
            ,
            uint256 virtualPrice
        ) = _getCollateral(_collateralAddress);
        
        
        uint256 moUSDdebt = (moUSDLoanAndInterest[_collateralAddress][msg.sender] * virtualPrice) / LOAN_SCALE;
        require( moUSDdebt >= _USDToVault, "Trying to return more moUSD than borrowed!");
        uint256 outstandingMoUSD = moUSDdebt - _USDToVault;
        uint256 colInUSD = _calculateProposedReturnedCapital(_collateralAddress, _loanNFTs, _partialPercentage);
        if(outstandingMoUSD >= TENTH_OF_CENT){ //ignore debts less than $0.001
            uint256 collateralLeft = _totalCollateralValue(_collateralAddress, msg.sender) - colInUSD;
            uint256 borrowMargin = (outstandingMoUSD * minOpeningMargin) / LOAN_SCALE;
            require(collateralLeft > borrowMargin , "Remaining debt fails to meet minimum margin!");
        }

        //record paying off loan principle before interest
        uint256 interestPaid;
        {
        //uint256 loanPrinciple = moUSDLoaned[_collateralAddress][msg.sender];
        if( moUSDLoaned[_collateralAddress][msg.sender] >= _USDToVault){
            //pay off loan principle first
            moUSDLoaned[_collateralAddress][msg.sender] = moUSDLoaned[_collateralAddress][msg.sender] - _USDToVault;
        }
        else{
            interestPaid = _USDToVault - moUSDLoaned[_collateralAddress][msg.sender];
            //loan principle is fully repaid so record this.
            moUSDLoaned[_collateralAddress][msg.sender] = 0;
        }
        }

        moUSDLoanAndInterest[_collateralAddress][msg.sender] = moUSDLoanAndInterest[_collateralAddress][msg.sender] - ((_USDToVault * LOAN_SCALE) / virtualPrice);
        
        
        //process return of NFTs now data validation is finished.
        // loanNFTids mapping is updated here too
        _decreaseLoanOrCollateral(_collateralAddress, msg.sender, _loanNFTs, _partialPercentage, _USDToVault, interestPaid);
        
        
        emit ClosedLoanNFT(msg.sender, _USDToVault, currencyKey, colInUSD);
        }

    /**
        Liquidation functions
     */
    
    function _calculateProposedReturnedCapital(
        address _collateralAddress, 
        CollateralNFTs memory _loanNFTs, 
        uint256 _partialPercentage
        ) internal view returns(uint256){

        uint256 proposedLiquidationAmount;
        for(uint256 i = 0; i < NFT_LIMIT; i++){
                if(_loanNFTs.slots[i] < NFT_LIMIT){
                    if(i == NFT_LIMIT -1){
                        //final slot is NFT that will be split if necessary
                        if((_partialPercentage > 0) ){
                            //determine the proposed percentage of the NFT's liquidity being liquidated.
                            require(_partialPercentage <= LOAN_SCALE, "partialPercentage greater than 100%");
                            proposedLiquidationAmount += 
                                                        (( _priceCollateral(IDepositReceipt(_collateralAddress), _loanNFTs.ids[i]) 
                                                        *_partialPercentage)/ LOAN_SCALE);
                        }
                    } 
                    else{
                        proposedLiquidationAmount += _priceCollateral(IDepositReceipt(_collateralAddress), _loanNFTs.ids[i]);
                    }
                }
                
            }
            
            return proposedLiquidationAmount;
    }

    function _returnAndSplitNFTs(
        address _collateralAddress, 
        address _loanHolder, 
        CollateralNFTs memory _loanNFTs, 
        uint256 _partialPercentage
        ) internal{

        IDepositReceipt depositReceipt = IDepositReceipt(_collateralAddress);
        NFTids storage userNFTs = loanNFTids[_collateralAddress][_loanHolder];
        for(uint256 i = 0; i < NFT_LIMIT; i++){
             //then we check this slot is being used, if not the id is `NOT_OWNED`
            if (_loanNFTs.ids[i] < NFT_LIMIT){
                //final slot is NFT that will be split if necessary, we skip this loop if partialPercentage = 100% or 0%
                if((i == NFT_LIMIT -1) && (_partialPercentage > 0) && (_partialPercentage < LOAN_SCALE) ){
                    //split the NFT based on the partialPercentage proposed
                    uint256 newId = depositReceipt.split(_loanNFTs.ids[i], _partialPercentage);
                    //send the new NFT to the user, no mapping to update as original id NFT remains with the vault.
                    depositReceipt.transferFrom(address(this), msg.sender, newId);
                    }
                else{
                    userNFTs.ids[_loanNFTs.slots[i]] = 0;
                    depositReceipt.transferFrom(address(this), msg.sender, _loanNFTs.ids[i]);
                } 
            }
        }
    }
    function _liquidate(
        address _loanHolder,
        address _collateralAddress,
        uint256 _collateralLiquidated,
        CollateralNFTs memory _loanNFTs,
        uint256 _partialPercentage,
        uint256 _moUSDReturned,
        bytes32 _currencyKey, 
        uint256 _virtualPrice
        ) internal {
        //record paying off loan principle before interest
        uint256 loanPrinciple = moUSDLoaned[_collateralAddress][_loanHolder];
        uint256 interestPaid;
        if( loanPrinciple >= _moUSDReturned){
            //pay off loan principle first
            moUSDLoaned[_collateralAddress][_loanHolder] = loanPrinciple - _moUSDReturned;
        }
        else {
            interestPaid = _moUSDReturned - loanPrinciple;
            //loan principle is fully repaid so record this.
            moUSDLoaned[_collateralAddress][_loanHolder] = 0;
        }

        //if non-zero we are not handling a bad debt so the loanAndInterest will need updating
        // this is semantic overloading so we must be careful here
        if(moUSDLoanAndInterest[_collateralAddress][_loanHolder] > 0){
            moUSDLoanAndInterest[_collateralAddress][_loanHolder] = 
                moUSDLoanAndInterest[_collateralAddress][_loanHolder] - 
                ((_moUSDReturned * LOAN_SCALE) / _virtualPrice);
        }
        else{ //here as moUSDLoanAndInterest are zero we must be handling a baddebt or complete payoff 
            //so  we wipe the principle as we are finished using it
            moUSDLoaned[_collateralAddress][_loanHolder] = 0;
        }
        

        _decreaseLoanOrCollateral(
            _collateralAddress,
            _loanHolder,
            _loanNFTs,
            _partialPercentage,
            _moUSDReturned,
            interestPaid
        );
        
        emit LiquidationNFT(
            _loanHolder, 
            msg.sender,
            _moUSDReturned, 
            _currencyKey, 
            _collateralLiquidated
        );
    }


       
    
    function viewLiquidatableAmount(
        uint256 _collateralAmount,
        uint256 _collateralPrice,
        uint256 _userDebt,
        uint256 _liquidatableMargin
        ) public pure returns(uint256){
        uint256 minimumCollateralPoint = _userDebt*_liquidatableMargin;
        uint256 actualCollateralPoint = _collateralAmount*_collateralPrice;
        if(minimumCollateralPoint <=  actualCollateralPoint){
            //in this case the loan is not liquidatable at all and so we return zero
            return 0;
        }
        uint256 numerator =  minimumCollateralPoint - actualCollateralPoint; 
        uint256 denominator = (_collateralPrice*LIQUIDATION_RETURN*_liquidatableMargin/LOAN_SCALE - _collateralPrice*LOAN_SCALE)/LOAN_SCALE;
        return(numerator  / denominator);

    }

     /**
      * @notice Anyone can liquidate any other undercollateralised loan.
      * @notice The max acceptable liquidation quantity is calculated using viewLiquidatableAmount
      * @notice this prevents full liquidation when partial liquidation would return recollaterize the loanHolder's debt 
      * @dev caller is paid 1-`LIQUIDATION_RETURN` as reward for calling the liquidation.
      * @dev In the event of full liquidation being insufficient the leftover debt is written off and an event tracking this is emitted.
      * @param _loanHolder address of loanee being liquidated.
      * @param _collateralAddress address of collateral token being used.
      * @param _loanNFTs structure containing the loan's NFT ids and the related slot it is stored in,
      * @dev don't trust user input for this, always verify the ids match the user given slot before using.
      * @notice the 4th nftId slot is always used for the partially liquidating NFT (if any exists)
      * @param _partialPercentage percentage of the partialNFT that will be liquidated (0-100%) 
      *                           expressed in LOAN_SCALE (i.e. 1 eth = 100%)
     */
    
    
        function callLiquidation(
            address _loanHolder,
            address _collateralAddress,
            CollateralNFTs memory _loanNFTs,
            uint256 _partialPercentage
        ) external whenNotPaused  
        {   
            _validMarketConditions(_collateralAddress, _loanHolder);
            for(uint256 i = 0; i < NFT_LIMIT; i++){
                require(_loanNFTs.slots[i] == 
                    _checkNFTOwnership(_collateralAddress, _loanNFTs.ids[i], _loanHolder),
                     "Incorrect NFT details inputted");
            }
            _updateVirtualPrice(block.timestamp, _collateralAddress);
            (
                bytes32 currencyKey,
                ,
                uint256 liquidatableMargin,
                ,
                ,
                uint256 virtualPrice
            ) = _getCollateral(_collateralAddress);
            
            uint256 moUSDBorrowed = (moUSDLoanAndInterest[_collateralAddress][_loanHolder] * virtualPrice) / LOAN_SCALE;
            uint256 totalUserCollateral = _totalCollateralValue(_collateralAddress, _loanHolder);
            uint256 proposedLiquidationAmount;
            { //scope block for liquidationAmount due to stack too deep
                uint256 liquidationAmount = viewLiquidatableAmount(totalUserCollateral, 1 ether, moUSDBorrowed, liquidatableMargin);
                require(liquidationAmount > 0 , "Loan not liquidatable");
            
                proposedLiquidationAmount = _calculateProposedReturnedCapital(_collateralAddress, _loanNFTs, _partialPercentage);
                require(proposedLiquidationAmount <= liquidationAmount, "excessive liquidation suggested");
                //require(proposedLiquidationAmount >= (liquidationAmount*LOWER_LIQUIDATION_BAND)/LOAN_SCALE, "Liquidation suggested too small");
                //is it safe to not have a lower bound for liquidation?
            }
            uint256 moUSDreturning = proposedLiquidationAmount*LIQUIDATION_RETURN/LOAN_SCALE;
            
            //if complete liquidation falls short of recovering the position we settle for complete liquidation
            if(proposedLiquidationAmount >= totalUserCollateral){
                if(moUSDBorrowed > moUSDreturning){
                    //if a user is being fully liquidated we will forgive any remaining debt so it
                    // doesn't roll over if they open a new loan of the same collateral.
                    emit BadDebtClearedNFT(_loanHolder, msg.sender, moUSDBorrowed - moUSDreturning, currencyKey);
                    moUSDLoanAndInterest[_collateralAddress][_loanHolder] = 0;
                }
            }    
            
            _liquidate(
                _loanHolder,
                _collateralAddress,
                proposedLiquidationAmount,
                _loanNFTs, //is it safe to use this, verify
                _partialPercentage,
                moUSDreturning,
                currencyKey,
                virtualPrice
                );
            
        }
    
}

