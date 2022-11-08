// SPDX-License-Identifier: MIT
// Vault_Lyra.sol for isomorph.loans
// Bug bounties available

pragma solidity =0.8.9; 
pragma abicoder v2;

// Interfaces
import "./interfaces/IisoUSDToken.sol";

import "./interfaces/ICollateralBook.sol";
import "./helper/interfaces/ILiquidityPoolAvalon.sol";
//dev debug
import "hardhat/console.sol";
//Open Zeppelin dependancies
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
//Time delayed governance
import "./RoleControl.sol";

uint256 constant VAULT_TIME_DELAY = 3 days;


contract Vault_Lyra is RoleControl(VAULT_TIME_DELAY), Pausable {

    using SafeERC20 for IERC20;
    //these mappings store the loan details of each users loan against each collateral.
    //collateral address => user address => quantity
    mapping(address => mapping(address => uint256)) public collateralPosted;
    mapping(address => mapping(address => uint256)) public isoUSDLoaned;
    mapping(address => mapping(address => uint256)) public isoUSDLoanAndInterest;

    //variables relating to access control and setting new roles
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    //Constants, private to reduce code size
    bytes32 private constant SUSD_CODE = "sUSD"; 
    uint256 public constant LIQUIDATION_RETURN = 95 ether /100; //95% returned on liquidiation
    uint256 private constant LOAN_SCALE = 1 ether; //base for division/decimal maths
    uint256 private constant TENTH_OF_CENT = 1 ether /1000; //$0.001

    //Enums
    enum AssetType {Synthetix_Synth, Lyra_LP} // collateral type identifiers to ensure the right valuation method is employed
    
    
    //Variables 
    //These three control max loans opened per day
    uint256 public dailyMax = 1_000_000 ether; //one million with 18d.p.
    uint256 public dayCounter = block.timestamp;
    uint256 public dailyTotal = 0;

    //This fee paid to the protocol by user on opening a loan
    uint256 public loanOpenFee = 1 ether /100; //1 percent opening fee.

    
    address public treasury;
    IisoUSDToken public isoUSD;
    ICollateralBook public collateralBook;    
   

    event OpenOrIncreaseLoan(address indexed user, uint256 loanTaken, bytes32 indexed collateralToken, uint256 collateralAmount); 
    event IncreaseCollateral(address indexed user, bytes32 indexed collateralToken, uint256 collateralAmount); 
    event ClosedLoan(address indexed user, uint256 loanAmountReturned, bytes32 indexed collateralToken, uint256 returnedCapital);
    event Liquidation(address indexed loanHolder, address indexed Liquidator, uint256 loanAmountReturned, bytes32 indexed collateralToken, uint256 liquidatedCapital);
    event BadDebtCleared(address indexed loanHolder, address indexed Liquidator, uint256 debtCleared, bytes32 indexed collateralToken);
    event ChangeDailyMax(uint256 newDailyMax, uint256 oldDailyMax);
    event ChangeOpenLoanFee(uint256 newOpenLoanFee, uint256 oldOpenLoanFee);

    event SystemPaused(address indexed pausedBy);
    event SystemUnpaused(address indexed unpausedBy);
    
    /// @notice basic checks to verify collateral being used exists
    /// @dev should be called by any external function modifying a loan
    function _collateralExists(address _collateralAddress) internal {
        require(collateralBook.collateralValid(_collateralAddress), "Unsupported collateral!");
    }

    modifier onlyPauser{
        bool validUser = hasRole(ADMIN_ROLE, msg.sender) || hasRole(PAUSER_ROLE, msg.sender);
        require(validUser, "Caller is not able to call pause");
        _;
    }
    
    
    constructor(
        address _isoUSD, //isoUSD address
        address _treasury, //treasury address
        address _collateralBook //collateral structure book address
        ){
        require(_isoUSD != address(0), "Zero Address used isoUSD");
        require(_treasury != address(0), "Zero Address used Treasury");
        require(_collateralBook != address(0), "Zero Address used Collateral");
        isoUSD = IisoUSDToken(_isoUSD);
        treasury = _treasury;
        collateralBook = ICollateralBook(_collateralBook);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
       
    } 

    /**
        External onlyAdmin or onlyPauser governance functions
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
    function setDailyMax(uint256 _newDailyMax) external onlyAdmin {
        require(_newDailyMax < 100_000_000 ether ); //sanity check, require less than 100 million opened per day
        emit ChangeDailyMax(_newDailyMax, dailyMax); //ignoring CEI pattern here
        dailyMax = _newDailyMax;
        
        
    }

    /// @notice openLoanFee can be set to 10% max, fee applied to all loans on opening
    function setOpenLoanFee(uint256 _newOpenLoanFee) external onlyAdmin {
        require(_newOpenLoanFee <= 1 ether /10 ); 
        emit ChangeOpenLoanFee(_newOpenLoanFee, loanOpenFee); //ignoring CEI pattern here
        loanOpenFee = _newOpenLoanFee;
    }

    /**
        Internal helper and check functions
     */

    /// @dev process for Lyra LP assets
    /// @dev this uses the liquidity Pool associated with the LP token to verify the circuit breaker is not active
    /// @dev to be overly cautious if the CB is active we revert
    /// @notice if any of them aren't the function will revert.
    /// @param _currencyKey the code used by synthetix to identify different synths, linked in collateral structure to collateral address
    function _checkIfCollateralIsActive(bytes32 _currencyKey) internal view {
            
             //Lyra LP tokens use their associated LiquidityPool to check if they're active
             ILiquidityPoolAvalon LiquidityPool = ILiquidityPoolAvalon(collateralBook.liquidityPoolOf(_currencyKey));
             bool isStale;
             uint circuitBreakerExpiry;
             //ignore first output as this is the token price and not needed yet.
             (, isStale, circuitBreakerExpiry) = LiquidityPool.getTokenPriceWithCheck();
             require( !(isStale), "Global Cache Stale, can't trade");
             require(circuitBreakerExpiry < block.timestamp, "Lyra Circuit Breakers active, can't trade");
    }
    /// @notice while this could be abused to DOS the system, given the openLoan fee this is an expensive attack to maintain
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
    

    /// @param _collateralAddress the address of the collateral token you are fetching
    /// @notice returns all collateral struct fields seperately so that functions requiring 
    /// @notice them can only locally store the ones they need
    function _getCollateral(address _collateralAddress) internal returns(
        bytes32 ,
        uint256 ,
        uint256 ,
        uint256 ,
        uint256 ,
        uint256,
        AssetType 
        ){
        ICollateralBook.Collateral memory collateral = collateralBook.collateralProps(_collateralAddress);
        return (
            collateral.currencyKey,
            collateral.minOpeningMargin,
            collateral.liquidatableMargin, 
            collateral.interestPer3Min, 
            collateral.lastUpdateTime, 
            collateral.virtualPrice,
            AssetType(collateral.assetType)
            );
    }

    /// @param _liquidityPool the address of the liquidityPool relating to the Lyra collateral we're using
    /// @notice there is a withdrawal fee for Lyra LPs, so we depreciate LP tokens by this to get the fair value
    /// @notice because the withdrawal fee is dynamic we must fetch it on each LP token valuation in case it's changed
    function _getWithdrawalFee(ILiquidityPoolAvalon _liquidityPool) internal view returns(
        uint256 ){
        ILiquidityPoolAvalon.LiquidityPoolParameters memory params = _liquidityPool.lpParams();
        return ( params.withdrawalFee );
    }


    /// @param _percentToPay the percentage of the total sum express as a fee
    /// @param _amount quantity of which to work out the percentage splits of
    /// @dev internal function used to calculate treasury fees on opening loans
    /// @return postFees is the quantity after the percentToPay has been deducted from it,
    /// @return feeToPay is the percentToPay of original _amount.
    function _findFees(uint256 _percentToPay, uint256 _amount) internal pure returns(uint256, uint256){
        uint256 feeToPay = ((_amount * _percentToPay) / LOAN_SCALE);
        uint256 postFees = _amount - feeToPay; //if the user loan is too small this will revert
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
            uint256 virtualPrice,

        ) = _getCollateral(_collateralAddress);
        uint256 timeDelta = _currentBlockTime - lastUpdateTime;
        //exit gracefully if two users call the function for the same collateral in the same 3min period
        uint256 threeMinuteDelta = timeDelta / 180; 
        if(threeMinuteDelta > 0) {
            for (uint256 i = 0; i < threeMinuteDelta; i++ ){
            virtualPrice = (virtualPrice * interestPer3Min) / LOAN_SCALE; 
            }
            collateralBook.vaultUpdateVirtualPriceAndTime(_collateralAddress, virtualPrice, _currentBlockTime);
        }
    }
    

     /**
      * @notice Only Vault can mint isoUSD.
      * @dev internal function to handle increases of loan
      * @param _loanAmount amount of isoUSD to be borrowed, some is used to pay the opening fee the rest is sent to the user.
     **/
    function _increaseLoan(uint256 _loanAmount) internal {
        uint256 userMint;
        uint256 userOpenFee;
        _checkDailyMaxLoans(_loanAmount);
        (userMint, userOpenFee) = _findFees(loanOpenFee, _loanAmount);
        isoUSD.mint(_loanAmount);
        //isoUSD reverts on transfer failure so we can safely ignore slither's warnings for it.
        //slither-disable-next-line unchecked-transfer
        isoUSD.transfer(msg.sender, userMint);
        //slither-disable-next-line unchecked-transfer
        isoUSD.transfer(treasury, userOpenFee);
    }
    /// @dev internal function used to increase user collateral on loan.
    /// @param _collateral the ERC20 compatible collateral to use, already set up in another function
    /// @param _colAmount the amount of collateral to be transfered to the vault. 
    function _increaseCollateral(IERC20 _collateral, uint256 _colAmount) internal {
        bool success = _collateral.transferFrom(msg.sender, address(this), _colAmount);
        require(success, "collateral transfer failed");
    }

    
    /// @dev internal function used to decrease user collateral on loan.
    /// @param _collateralAddress the ERC20 compatible collateral Address NOT already set up as an IERC20.
    /// @param _amount the amount of collateral to be transfered back to the user.
    /// @param _USDReturned quantity of isoUSD being returned to the vault, this can be zero.
    /// @param _interestPaid quantity of interest paid on closing loan, this is transfered to the treasury , this can be zero
    function _decreaseLoan(address _collateralAddress, uint256 _amount, uint256 _USDReturned, uint256 _interestPaid) internal {
        IERC20 collateral = IERC20(_collateralAddress);
        //_interestPaid is always less thn _USDReturned so this is safe.
        uint256 USDBurning = _USDReturned - _interestPaid;
        //slither-disable-next-line unchecked-transfer
        isoUSD.transferFrom(msg.sender, address(this), _USDReturned);
        //burn original loan principle
        isoUSD.burn(address(this), USDBurning);
        //transfer interest earned on loan to treasury
        //slither-disable-next-line unchecked-transfer
        isoUSD.transfer(treasury, _interestPaid);
        bool success = collateral.transfer(msg.sender, _amount);
        require(success, "collateral transfer failed");
    }


    /// @notice function required because of stack depth on closeLoan, only called by closeLoan function.
    /// @param _collateralAddress address of the collateral token being used.
    /// @param _collateralToUser quantity of collateral proposed to be returned to user closing loan
    /// @param _USDToVault proposed quantity of isoUSD being returned (burnt) to the vault on closing the loan.
    function _closeLoanChecks(address _collateralAddress, uint256 _collateralToUser, uint256 _USDToVault) internal view {
        require(collateralPosted[_collateralAddress][msg.sender] >= _collateralToUser, "User never posted this much collateral!");
        require(isoUSD.balanceOf(msg.sender) >= _USDToVault, "Insufficient user isoUSD balance!");
    }

    /**
        Public functions 
    */


    //isoUSD is assumed to be valued at $1 by all of the system to avoid oracle attacks. 
    /// @param _currencyKey code used by Synthetix to identify each collateral/synth
    /// @param _amount quantity of collateral to price into sUSD
    /// @return returns the value of the given collateral in sUSD which is assumed to be pegged at $1.
    function priceCollateralToUSD(bytes32 _currencyKey, uint256 _amount) public view returns(uint256){
         //The LiquidityPool associated with the LP Token is used for pricing
        ILiquidityPoolAvalon LiquidityPool = ILiquidityPoolAvalon(collateralBook.liquidityPoolOf(_currencyKey));
        //we have already checked for stale greeks so here we call the basic price function.
        uint256 tokenPrice = LiquidityPool.getTokenPrice();          
        uint256 withdrawalFee = _getWithdrawalFee(LiquidityPool);
        uint256 USDValue  = (_amount * tokenPrice) / LOAN_SCALE;
        //we remove the Liquidity Pool withdrawalFee 
        //as there's no way to remove the LP position without paying this.
        uint256 USDValueAfterFee = USDValue * (LOAN_SCALE- withdrawalFee)/LOAN_SCALE;
        return(USDValueAfterFee);
    }

    /**
        External user loan interaction functions
     */


     /**
      * @notice Only Vaults can mint isoUSD.
      * @dev Mints 'USDborrowed' amount of isoUSD to vault and transfers to msg.sender and emits transfer event.
      * @param _collateralAddress address of collateral token being used.
      * @param _colAmount amount of collateral tokens being used.
      * @param _USDborrowed amount of isoUSD to be minted, it is then split into the amount sent and the opening fee.
     **/
    function openLoan(
        address _collateralAddress,
        uint256 _colAmount,
        uint256 _USDborrowed
        ) external whenNotPaused 
        {
        _collateralExists(_collateralAddress);
        IERC20 collateral = IERC20(_collateralAddress);
        
        require(collateral.balanceOf(msg.sender) >= _colAmount, "User lacks collateral quantity!");
        //make sure virtual price is related to current time before fetching collateral details
        //slither-disable-next-line reentrancy-vulnerabilities-1
        _updateVirtualPrice(block.timestamp, _collateralAddress);  
        
        (   
            bytes32 currencyKey,
            uint256 minOpeningMargin,
            ,
            ,
            ,
            uint256 virtualPrice,
            
        ) = _getCollateral(_collateralAddress);
        //check for frozen or paused collateral
        _checkIfCollateralIsActive(currencyKey);
        //make sure the total isoUSD borrowed doesn't exceed the opening borrow margin ratio
        uint256 colInUSD = priceCollateralToUSD(currencyKey, _colAmount + collateralPosted[_collateralAddress][msg.sender]);
        uint256 totalUSDborrowed = _USDborrowed +  (isoUSDLoanAndInterest[_collateralAddress][msg.sender] * virtualPrice)/LOAN_SCALE;
        uint256 borrowMargin = (totalUSDborrowed * minOpeningMargin) / LOAN_SCALE;
        require(colInUSD >= borrowMargin, "Minimum margin not met!");

        //update mappings with new loan amounts
        collateralPosted[_collateralAddress][msg.sender] = collateralPosted[_collateralAddress][msg.sender] + _colAmount;
        isoUSDLoaned[_collateralAddress][msg.sender] = isoUSDLoaned[_collateralAddress][msg.sender] + _USDborrowed;
        isoUSDLoanAndInterest[_collateralAddress][msg.sender] = isoUSDLoanAndInterest[_collateralAddress][msg.sender] + ((_USDborrowed * LOAN_SCALE) / virtualPrice);
        
        emit OpenOrIncreaseLoan(msg.sender, _USDborrowed, currencyKey, _colAmount);

        //Now all effects are handled, transfer the assets so we follow CEI pattern
        _increaseCollateral(collateral, _colAmount);
        _increaseLoan(_USDborrowed);
        
        
    }


    /**
      * @dev Increases collateral supplied against an existing loan. 
      * @notice Checks adding the collateral will keep the user above liquidation, 
      * @notice this debatable check isn't technically needed but feels fairer to end users.
      * @param _collateralAddress address of collateral token being used.
      * @param _colAmount amount of collateral tokens being used.
     **/
    function increaseCollateralAmount(
        address _collateralAddress,
        uint256 _colAmount
        ) external whenNotPaused 
        {
        _collateralExists(_collateralAddress);
        require(collateralPosted[_collateralAddress][msg.sender] > 0, "No existing collateral!"); //feels like semantic overloading and also problematic for dust after a loan is 'closed'
        require(_colAmount > 0 , "Zero amount"); //Not strictly needed, prevents event spamming though
        //make sure virtual price is related to current time before fetching collateral details
        //slither-disable-next-line reentrancy-vulnerabilities-1
        _updateVirtualPrice(block.timestamp, _collateralAddress);
        IERC20 collateral = IERC20(_collateralAddress);
        require(collateral.balanceOf(msg.sender) >= _colAmount, "User lacks collateral amount");
        (   
            bytes32 currencyKey,
            ,
            uint256 liquidatableMargin,
            ,
            ,
            uint256 virtualPrice,
            
        ) = _getCollateral(_collateralAddress);
        //check for frozen or paused collateral
        _checkIfCollateralIsActive(currencyKey);
        //debatable check begins here 
        uint256 totalCollat = collateralPosted[_collateralAddress][msg.sender] + _colAmount;
        uint256 colInUSD = priceCollateralToUSD(currencyKey, totalCollat);
        uint256 USDborrowed = (isoUSDLoanAndInterest[_collateralAddress][msg.sender] * virtualPrice) / LOAN_SCALE;
        uint256 borrowMargin = (USDborrowed * liquidatableMargin) / LOAN_SCALE;
        require(colInUSD >= borrowMargin, "Liquidation margin not met!");
        //debatable check ends here
        //update mapping with new collateral amount
        collateralPosted[_collateralAddress][msg.sender] = collateralPosted[_collateralAddress][msg.sender] + _colAmount;
        emit IncreaseCollateral(msg.sender, currencyKey, _colAmount);
        //Now all effects are handled, transfer the collateral so we follow CEI pattern
        _increaseCollateral(collateral, _colAmount);
        
    }


     /**
      * @notice Only Vault can destroy isoUSD.
      * @dev destroys USDreturned of isoUSD held by caller, returns user collateral, close debt 
      * @dev if debt remains, checks minimum collateral ratio is upheld 
      * @dev if cost of a transaction can be <$0.01 YOU MUST UPDATE TENTH_OF_CENT check otherwise users can open microloans and close, withdrawing collateral without repaying. 
      * @param _collateralAddress address of collateral token being used.
      * @param _collateralToUser amount of collateral tokens being returned to user.
      * @param _USDToVault amount of isoUSD to be burnt.
     **/

    function closeLoan(
        address _collateralAddress,
        uint256 _collateralToUser,
        uint256 _USDToVault
        ) external whenNotPaused  
        {
        _collateralExists(_collateralAddress);
        _closeLoanChecks(_collateralAddress, _collateralToUser, _USDToVault);
        //make sure virtual price is related to current time before fetching collateral details
        //slither-disable-next-line reentrancy-vulnerabilities-1
        _updateVirtualPrice(block.timestamp, _collateralAddress);
        (   
            bytes32 currencyKey,
            uint256 minOpeningMargin,
            ,
            ,
            ,
            uint256 virtualPrice,
            
        ) = _getCollateral(_collateralAddress);
        //check for frozen or paused collateral
        _checkIfCollateralIsActive(currencyKey);
        uint256 isoUSDdebt = (isoUSDLoanAndInterest[_collateralAddress][msg.sender] * virtualPrice) / LOAN_SCALE;
        require( isoUSDdebt >= _USDToVault, "Trying to return more isoUSD than borrowed!");
        uint256 outstandingisoUSD = isoUSDdebt - _USDToVault;
        if(outstandingisoUSD >= TENTH_OF_CENT){ //ignore leftover debts less than $0.001
            uint256 collateralLeft = collateralPosted[_collateralAddress][msg.sender] - _collateralToUser;
            uint256 colInUSD = priceCollateralToUSD(currencyKey, collateralLeft); 
            uint256 borrowMargin = (outstandingisoUSD * minOpeningMargin) / LOAN_SCALE;
            require(colInUSD > borrowMargin , "Remaining debt fails to meet minimum margin!");
        }

        //record paying off loan principle before interest
        //slither-disable-next-line uninitialized-local-variables
        uint256 interestPaid;
        uint256 loanPrinciple = isoUSDLoaned[_collateralAddress][msg.sender];
        if( loanPrinciple >= _USDToVault){
            //pay off loan principle first
            isoUSDLoaned[_collateralAddress][msg.sender] = loanPrinciple - _USDToVault;
        }
        else{
            interestPaid = _USDToVault - loanPrinciple;
            //loan principle is fully repaid so record this.
            isoUSDLoaned[_collateralAddress][msg.sender] = 0;
        }

        //update mappings with reduced amounts
        isoUSDLoanAndInterest[_collateralAddress][msg.sender] = isoUSDLoanAndInterest[_collateralAddress][msg.sender] - ((_USDToVault * LOAN_SCALE) / virtualPrice);
        collateralPosted[_collateralAddress][msg.sender] = collateralPosted[_collateralAddress][msg.sender] - _collateralToUser;
        emit ClosedLoan(msg.sender, _USDToVault, currencyKey, _collateralToUser);
        //Now all effects are handled, transfer the assets so we follow CEI pattern
        _decreaseLoan(_collateralAddress, _collateralToUser, _USDToVault, interestPaid);
        }
    
    

    /**
        Liquidation functions
     
    */
    // @dev this functions trusts all inputs, never call it without having done all validation first.
    function _liquidate(
        address _loanHolder,
        address _collateralAddress,
        uint256 _collateralLiquidated,
        uint256 _isoUSDReturned,
        bytes32 _currencyKey, 
        uint256 _virtualPrice
        ) internal {
        //IERC20 collateral = IERC20(_collateralAddress);
        //record paying off loan principle before interest
            uint256 loanPrinciple = isoUSDLoaned[_collateralAddress][_loanHolder];
            //slither-disable-next-line uninitialized-local-variables
            uint256 interestPaid;
            if( loanPrinciple >= _isoUSDReturned){
                //pay off loan principle first
                isoUSDLoaned[_collateralAddress][_loanHolder] = loanPrinciple - _isoUSDReturned;
            }
            else{
                interestPaid = _isoUSDReturned - loanPrinciple;
                //loan principle is fully repaid so record this.
                isoUSDLoaned[_collateralAddress][_loanHolder] = 0;
            }
        //if non-zero we are not handling a bad debt so the loanAndInterest will need updating
        if(isoUSDLoanAndInterest[_collateralAddress][_loanHolder] > 0){
            //
            isoUSDLoanAndInterest[_collateralAddress][_loanHolder] = isoUSDLoanAndInterest[_collateralAddress][_loanHolder] - ((_isoUSDReturned * LOAN_SCALE) / _virtualPrice);
        }
        else{
            //now that we've determined how much principle and interest is being repaid we wipe the principle for bad debts too
            isoUSDLoaned[_collateralAddress][_loanHolder] = 0;
        }
        
        collateralPosted[_collateralAddress][_loanHolder] = collateralPosted[_collateralAddress][_loanHolder] - _collateralLiquidated;
        
        emit Liquidation(_loanHolder, msg.sender, _isoUSDReturned, _currencyKey, _collateralLiquidated);
        //finally handle transfer of collateral and isoUSD.
        _decreaseLoan(_collateralAddress, _collateralLiquidated, _isoUSDReturned, interestPaid);
    }


       
/**
* @notice This function handles the maths of determining when a loan is liquidatable and is written
          such that users can view the liquidatable amount gas free by being a pure function, 
          enabling website integration or for liquidator bot when determining which debts to liquidate
**/ 
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
      * @dev checks that partial liquidation would be insufficient to recollaterize the loanHolder's debt 
      * @dev caller is paid 1e18 -`LIQUIDATION_RETURN` as reward for calling the liquidation.
      * @dev In the event of full liquidation being insufficient the leftover debt is written off and an event tracking this is emitted.
      * @param _loanHolder address of loanee being liquidated.
      * @param _collateralAddress address of collateral token being used.
     **/
        
        function callLiquidation(
            address _loanHolder,
            address _collateralAddress
        ) external whenNotPaused  
        {   
            _collateralExists(_collateralAddress);
            require(_loanHolder != address(0), "Zero address used"); 
             //make sure virtual price is related to current time before fetching collateral details
            //slither-disable-next-line reentrancy-vulnerabilities-1
            _updateVirtualPrice(block.timestamp, _collateralAddress);
            (
                bytes32 currencyKey,
                ,
                uint256 liquidatableMargin,
                ,
                ,
                uint256 virtualPrice,
                
            ) = _getCollateral(_collateralAddress);
            //check for frozen or paused collateral
            _checkIfCollateralIsActive(currencyKey);
            //check how much of the specified loan should be closed
            uint256 isoUSDBorrowed = (isoUSDLoanAndInterest[_collateralAddress][_loanHolder] * virtualPrice) / LOAN_SCALE;
            uint256 totalUserCollateral = collateralPosted[_collateralAddress][_loanHolder];
            uint256 currentPrice = priceCollateralToUSD(currencyKey, LOAN_SCALE); //assumes LOAN_SCALE = 1 ether, i.e. one unit of collateral!
            uint256 liquidationAmount = viewLiquidatableAmount(totalUserCollateral, currentPrice, isoUSDBorrowed, liquidatableMargin);
            require(liquidationAmount > 0 , "Loan not liquidatable");
            //if complete liquidation falls short of recovering the position we settle for complete liquidation
            if(liquidationAmount > totalUserCollateral){
                liquidationAmount = totalUserCollateral;
            }
            uint256 isoUSDreturning = liquidationAmount*currentPrice*LIQUIDATION_RETURN/LOAN_SCALE/LOAN_SCALE;  
            
            //if the liquidation is the entire loan we need to record more
            if(totalUserCollateral == liquidationAmount){
                //and some of the loan is not being repaid.
                if(isoUSDBorrowed > isoUSDreturning){
                    //if a user is being fully liquidated we will forgive any remaining debt so it
                    // doesn't roll over if they open a new loan of the same collateral.
                    delete isoUSDLoanAndInterest[_collateralAddress][_loanHolder];
                    emit BadDebtCleared(_loanHolder, msg.sender, isoUSDBorrowed - isoUSDreturning, currencyKey);
                    
                }
            }
            //finally we call an internal function that updates mappings
            // burns the liquidator's isoUSD and transfers the collateral to the liquidator as payment
            _liquidate(_loanHolder, _collateralAddress, liquidationAmount, isoUSDreturning, currencyKey, virtualPrice);
            
        } 
}