module lemonjet::shares {

use sui::balance::{ Balance };
public struct SharesType<phantom T> has drop {}

public struct Shares<phantom T> has key {
id: UID,
balance: Balance<SharesType<T>>
}


public(package) fun create_shares_type<T>(): SharesType<T> {
    SharesType {}
}


public fun value<T>(self: &Shares<T>): u64 {
    self.balance.value()
}


public  fun join<T>(self: &mut Shares<T>, s: Shares<T>) {
    let Shares { id, balance } = s;
    id.delete();
    self.balance.join(balance);
}

public fun split<T>(self: &mut Shares<T>, split_amount: u64, ctx: &mut TxContext): Shares<T> {
    Shares {
        id: object::new(ctx),
        balance: self.balance.split(split_amount),
}
}

public fun transfer<T>(self: Shares<T>, recipient: address) {
    transfer::transfer(self, recipient);
}

public fun from_balance<T>(balance: Balance<SharesType<T>>, ctx: &mut TxContext): Shares<T> {
    Shares { id: object::new(ctx), balance }
}

public fun into_balance<T>(shares: Shares<T>): Balance<SharesType<T>> {
    let Shares { id, balance } = shares;
    id.delete();
    balance
}
}