## SOLUTION Monitor.sol: checkFlashLoan()'s unintended pausing of Vault

Owner calling this function **any time** since ``end`` timestamp will pause the Vault.

- ``owner`` address calls ``checkFlashLoan()`` on Monitor with any ``amount``
  
- in ``checkFlashLoan()`` makes a call ``vault.flashLoan()`` in its ``try`` section and provides itself as ``reciever``
  
- in its execution of ``flashLoan()`` Vault makes a call ``receiver.onFlashLoan()``, where ``reciever`` is Monitor contract, and this call **reverts**.

- ``catch`` part is executed, Vault is paused and ownership is transfered to ``owner`` of Monitor

#### Cause of revert

Any call to ``flashLoan()`` function since ``end`` timepoint results into ``fee`` variable on line 91 of Vault contract to be **non-zero**.

When executing ``checkFlashLoan()``, there is a call made to Monitor's ``onFlashLoan()``.

On line 27 there is ``fee != 0``, and as mentiond before, any call since ``end`` timestamp involves this ``fee`` being non-zero.


## OTHER FINDINGS

### Vault.sol: onFlashLoan() bad approval

The if statement in this function implies it can only be called by Vault contract.

Any call to ``flashLoan()`` function since ``end`` timepoint results into ``fee`` variable on line 91 of Vault contract to be **non-zero**.

- on line 31 Monitor contract approves Vault contract for ``amount``, not ``amount + fee`` as expected on line 100 of Vault.

- line 100 of Monitor would **revert**

Vault can't pull ``amount + fee`` because it has insufficient allowance. It is only approved for ``amount``.

This results in ``checkFlashLoan()`` on Monitor cotract unintentionally pausing Vault.

### Monitor.sol: flashFee() unintended charging of fee for maximum amount flash loans before grace period ends

Taking max flash loan will charge fee **before grace period ends**.

- on line 61 of Vault's code if statment is ``false`` when input to the function is equal to ``maxFlashLoan()``

This may result in fee being charged, since ``flashFee()`` is called by ``flashLoan()`` to calculate ``fee``.




1. Vault.sol line 61: fee will be returned even before GRACE_PERIOD ends since check fails when _amount = maxFlashLoan()

Causes to charge fee for max flash loan