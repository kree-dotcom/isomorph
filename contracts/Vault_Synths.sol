// SPDX-License-Identifier: MIT
// Vault_Synths.sol for isomorph.loans
// Bug bounties available

pragma solidity =0.8.9; 
pragma abicoder v2;

// External Synthetix interfaces
import "./helper/interfaces/ISynthetix.sol";
import "./helper/interfaces/IExchangeRates.sol";
import "./helper/interfaces/IAddressResolver.sol";
import "./helper/interfaces/IExchanger.sol";
import "./helper/interfaces/ISystemStatus.sol";

//External OpenZeppelin dependancy
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

//Vault Base for common functions
import "./Vault_Base_ERC20.sol";

//chainlink aggregator interface for pricefeed
import "./interfaces/IAggregatorV3.sol";
import "./interfaces/IAccessControlledOffchainAggregator.sol";



contract Vault_Synths is Vault_Base_ERC20, ReentrancyGuard {

    //Constants, private to reduce code size
    bytes32 private constant SUSD_CODE = "sUSD"; 
    bytes32 private constant EXCHANGE_RATES = "ExchangeRates";
    bytes32 private constant EXCHANGER = "Exchanger";
    uint256 private constant ONE_HUNDRED_DOLLARS = 100 ether;
    uint256 internal HEARTBEAT = 24 hours; //sUSD Chainlink Optimism heartbeat time, not a constant for testing purposes
    uint256 private constant ORACLE_BASE = 1e8; // ten to the power of the number of decimals given to the price feed
    
    //Optimism Mainnet addresses
    
    address public constant ADDRESS_RESOLVER = 0x95A6a3f44a70172E7d50a9e28c85Dfd712756B8C;
    IAddressResolver addressResolver = IAddressResolver(ADDRESS_RESOLVER);

    address public constant SYSTEM_STATUS = 0xE8c41bE1A167314ABAF2423b72Bf8da826943FFD;
    ISystemStatus private synthetixSystemStatus = ISystemStatus(SYSTEM_STATUS);

    address public constant PRICE_FEED = 0x7f99817d87baD03ea21E05112Ca799d715730efe;
    IAggregatorV3 priceFeed = IAggregatorV3(PRICE_FEED);
    
   
    
    
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
        Internal helper and check functions
     */

    /// @dev process for Synthetix assets
    /// @dev leverages synthetix system to verify that the collateral in question is currently trading
    /// @dev this prevents people frontrunning closed weekend markets for expected price crashes etc
    /// @notice this call verifies Synthetix system, exchange and the synths in question are all available.
    /// @notice if any of them aren't the function will revert.
    /// @param _currencyKey the code used by synthetix to identify different synths, linked in collateral structure to collateral address
    function _checkIfCollateralIsActive(bytes32 _currencyKey) internal view override {
             synthetixSystemStatus.requireExchangeBetweenSynthsAllowed(_currencyKey, SUSD_CODE);
         
    }

    /**
        Public functions 
    */

    function getOraclePrice() public view returns (uint256 ) {
        (
            uint80 roundID,
            int signedPrice,
            /*uint startedAt*/,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        //check for Chainlink oracle deviancies, force a revert if any are present. Helps prevent a LUNA like issue
        require(signedPrice > 0, "Negative Oracle Price");
        require(timeStamp >= block.timestamp - HEARTBEAT , "Stale pricefeed");
        IAccessControlledOffchainAggregator  aggregator = IAccessControlledOffchainAggregator(priceFeed.aggregator());
        //fetch the pricefeeds hard limits so we can be aware if these have been reached.
        int192 tokenMinPrice = aggregator.minAnswer();
        int192 tokenMaxPrice = aggregator.maxAnswer();
        //The min/maxPrice is the smallest/largest value the aggregator will post and so if it is reached we can no longer trust the oracle price hasn't gone beyond it.
        require(signedPrice < tokenMaxPrice, "Upper price bound breached"); 
        require(signedPrice > tokenMinPrice, "Lower price bound breached");
        require(answeredInRound >= roundID, "round not complete");
        uint256 price = uint256(signedPrice);
        return price;


    }

    //isoUSD is assumed to be valued at $1 by all of the system to avoid oracle attacks. 
    /// @param _currencyKey code used by Synthetix to identify each collateral/synth
    /// @param _amount quantity of collateral to price into sUSD
    /// @return returns the value of the given synth in sUSD after Synthetix exchange fees.
    function priceCollateralToUSD(bytes32 _currencyKey, uint256 _amount) public view override returns(uint256){
        //As it is a synth use synthetix for pricing, we fetch the Synthetix pricing contracts each time as they occasionally are updated.
        IExchanger exchanger = IExchanger(addressResolver.getAddress(EXCHANGER));
        IExchangeRates exchangeRates = IExchangeRates(addressResolver.getAddress(EXCHANGE_RATES));
        uint256 exchangeAmount = exchangeRates.effectiveValue(_currencyKey, _amount, SUSD_CODE);
        uint256 fee = exchanger.feeRateForExchange(_currencyKey, SUSD_CODE);
        uint256 exchangeAmountAfterFee = (exchangeAmount * (LOAN_SCALE - fee))/LOAN_SCALE;
        uint256 oraclePrice = getOraclePrice();
        uint256 USDValue = (exchangeAmountAfterFee*oraclePrice) / ORACLE_BASE;
        return (USDValue);      
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
        ) external override whenNotPaused nonReentrant
        {
        _collateralExists(_collateralAddress);
        require(!collateralBook.collateralPaused(_collateralAddress), "Paused collateral!");
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
        require(totalUSDborrowed >= ONE_HUNDRED_DOLLARS, "Loan Requested too small"); 
        uint256 borrowMargin = (totalUSDborrowed * minOpeningMargin) / LOAN_SCALE;
        require(colInUSD >= borrowMargin, "Minimum margin not met!");

        //update mappings with new loan amounts
        collateralPosted[_collateralAddress][msg.sender] = collateralPosted[_collateralAddress][msg.sender] + _colAmount;
        isoUSDLoaned[_collateralAddress][msg.sender] = isoUSDLoaned[_collateralAddress][msg.sender] + _USDborrowed;
        isoUSDLoanAndInterest[_collateralAddress][msg.sender] = isoUSDLoanAndInterest[_collateralAddress][msg.sender] + ((_USDborrowed * LOAN_SCALE) / virtualPrice);
        
        emit OpenOrIncreaseLoan(msg.sender, _USDborrowed, currencyKey, _colAmount);

        //Now all effects are handled, transfer the assets so we follow CEI pattern
        _increaseCollateral(collateral, _colAmount);
        _increaseLoan(_USDborrowed, _collateralAddress);
        
        
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
        ) external override nonReentrant
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
        ) external override nonReentrant
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
        if(isoUSDdebt < _USDToVault){
            _USDToVault = isoUSDdebt;
        }
        uint256 outstandingisoUSD = isoUSDdebt - _USDToVault;
        if((outstandingisoUSD > 0) && (_collateralToUser > 0)){ //check for leftover debt
            uint256 collateralLeft = collateralPosted[_collateralAddress][msg.sender] - _collateralToUser;
            uint256 colInUSD = priceCollateralToUSD(currencyKey, collateralLeft); 
            uint256 borrowMargin = (outstandingisoUSD * minOpeningMargin) / LOAN_SCALE;
            require(colInUSD >= borrowMargin , "Remaining debt fails to meet minimum margin!");
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
        ) external override nonReentrant
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
                    //if a user is being fully liquidated we will forgive any remaining debt and interest so it
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