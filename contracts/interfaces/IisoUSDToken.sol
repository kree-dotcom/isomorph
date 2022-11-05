pragma solidity =0.8.9;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IisoUSDToken is IERC20 {
    
  
     /**
      * @notice Only owner can burn isoUSD
      * @dev burns 'amount' of tokens to address 'account', and emits Transfer event to 
      * to zero address.
      * @param account The address of the token holder
      * @param amount The amount of token to be burned.
     **/
    function burn(address account, uint256 amount) external;
    /**
      * @notice Only owner can mint isoUSD
      * @dev Mints 'amount' of tokens to address 'account', and emits Transfer event
      * @param amount The amount of token to be minted
     **/
    function mint( uint amount) external;
}
