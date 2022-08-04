//Isomorph.loans moUSDToken.sol
//SPDX-License-Identifier: MIT
//https://github.com/kree-dotcom/isomorph

pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./RoleControl.sol";

uint256 constant MOUSD_TIME_DELAY = 3; //days;

contract moUSDToken is  ERC20, RoleControl(MOUSD_TIME_DELAY) {
    
    // Role based access control, minters can mint or burn moUSD
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");  


    constructor() ERC20("IsomorphUSD", "moUSD"){
        //we dont want the `DEFAULT_ADMIN_ROLE` to exist as this doesn't require a 
        // time delay to add/remove any role and so is dangerous. 
        //So we ignore it and set our weaker admin role.
        _setupRole(ADMIN_ROLE, msg.sender);
    }

    modifier onlyMinter{
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _;
    }
    
    
    
     /**
      * @notice Only minters can burn moUSD
      * @dev burns 'amount' of tokens to address 'account', and emits Transfer event to 
      * to zero address.
      * @param _account The address of the token holder
      * @param _amount The amount of token to be burned.
     **/
    function burn(address _account, uint256 _amount) external onlyMinter{
        _burn(_account, _amount);
    }
    /**
      * @notice Only minters can mint moUSD
      * @dev Mints 'amount' of tokens to address 'account', and emits Transfer event
      * @param _amount The amount of token to be minted
     **/
    function mint( uint _amount) external onlyMinter {
        _mint( msg.sender, _amount);
    }
}