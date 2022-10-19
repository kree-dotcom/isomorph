# RoleControl.sol Functions and purposes

`RoleControl` is a contract intended to be inherited by other contracts. It handles the setting of roles and the timelocked addition of new roles. It is based on the OpenZeppelin library AccessControl which it inherits. All state changing functions are only callable by an Admin.


## Modifiers

- onlyAdmin
This modifer allows only `ADMIN_ROLE` accounts to execute a function.

## Functions

- proposeAddRole
The first stage to adding a role is to call this function. The proposed account, role and nonce are stored as is the hash of these three values.
The addition of a new role is timelocked with a delay specified by the constructor (usually 3 days). Adding roles is restricted to the Admin address, care must be taken if operating on multiple chains as a proposeAddRole transaction could be repeated, in the event Isomorph expands to another chain RoleControl will be modified to prevent attacks like this.

- addRole
This is the second stage of adding a role. First the supplied data is validated. Then we check the timelock period has passed since the role addition was proposed. Then once these checks pass we add the role and emit an event to log this. Because we only store one Role change at a time repeatedly calling this function has no impact, the calls would be idempotent.

- removeRole
Removing a role has no timelock, the action is instantanious to give a method to react to an account being hijacked in some way. First we check the account specified has the role we are trying to remove then we revoke the role and emit and event. 
