#!perl

use Test::More tests => 64;

diag("Test features of Conditional Negative Balances code.");

use constant WORKSTATION_NAME => 'BR1-test-09-lp1198465_neg_balances.t';
use constant WORKSTATION_LIB => 4;

use strict; use warnings;

use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/cleanse_ISO8601/;
use OpenILS::Utils::TestUtils;
my $script = OpenILS::Utils::TestUtils->new();
use Data::Dumper;

our $apputils   = "OpenILS::Application::AppUtils";

my ($patron_id, $patron_usrname, $xact_id, $item_id, $item_barcode);
my ($summary, $payment_blob, $pay_resp, $item_req, $checkin_resp);
my $user_obj;
my $storage_ses = $script->session('open-ils.storage');


sub retrieve_patron {
    my $patron_id = shift;

    my $user_req = $storage_ses->request('open-ils.storage.direct.actor.user.retrieve', $patron_id);
    if (my $user_resp = $user_req->recv) {
        if (my $patron_obj = $user_resp->content) {
            return $patron_obj;
        }
    }
    return 0;
}

sub fetch_billable_xact_summary {
    my $xact_id = shift;
    my $ses = $script->session('open-ils.cstore');
    my $req = $ses->request(
        'open-ils.cstore.direct.money.billable_transaction_summary.retrieve',
        $xact_id);

    if (my $resp = $req->recv) {
        return $resp->content;
    } else {
        return 0;
    }
}

sub pay_bills {
    my $payment_blob = shift;
    my $resp = $apputils->simplereq(
        'open-ils.circ',
        'open-ils.circ.money.payment',
        $script->authtoken,
        $payment_blob,
        $user_obj->last_xact_id
    );

    #refetch user_obj to get latest last_xact_id
    $user_obj = retrieve_patron($patron_id)
        or die 'Could not refetch patron';

    return $resp;
}

sub void_bills {
    my $billing_ids = shift; #array ref
    my $resp = $apputils->simplereq(
        'open-ils.circ',
        'open-ils.circ.money.billing.void',
        $script->authtoken,
        @$billing_ids
    );

    return $resp;
}

#----------------------------------------------------------------
# The tests...  assumes stock sample data, full-auto install by
# eg_wheezy_installer.sh, etc.
#----------------------------------------------------------------

# Connect to Evergreen
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff'});
ok( $script->authtoken, 'Have an authtoken');

my $ws = $script->register_workstation(WORKSTATION_NAME,WORKSTATION_LIB);
ok( ! ref $ws, 'Registered a new workstation');

$script->logout();
$script->authenticate({
    username => 'admin',
    password => 'demo123',
    type => 'staff',
    workstation => WORKSTATION_NAME});
ok( $script->authtoken, 'Have an authtoken associated with the workstation');


### TODO: verify that stock data is ready for testing

### Setup Org Unit Settings that apply to all test cases

my $org_id = 1; #CONS
my $settings = {
    'circ.max_item_price' => 50,
    'circ.min_item_price' => 50,
    'circ.void_lost_on_checkin' => 1
};

$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

# Setup first patron
$patron_id = 4;
$patron_usrname = '99999355250';

# Look up the patron
if ($user_obj = retrieve_patron($patron_id)) {
    is(
        ref $user_obj,
        'Fieldmapper::actor::user',
        'open-ils.storage.direct.actor.user.retrieve returned aou object'
    );
    is(
        $user_obj->usrname,
        $patron_usrname,
        'Patron with id = ' . $patron_id . ' has username ' . $patron_usrname
    );
}


##############################
# 1. No Prohibit Negative Balance Settings Are Enabled, Payment Made
##############################

### Setup use case variables
$xact_id = 1;
$item_id = 2;
$item_barcode = 'CONC4000037';
$org_id = 1; #CONS

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 1: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### pay the whole bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '50.00' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Remaining balance of 0.00 after payment'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            ref $item,
            'Fieldmapper::asset::copy',
            'open-ils.storage.direct.asset.copy.retrieve returned acp object'
        );
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '-50.00',
    'Patron has a negative balance (credit) of 50.00 due to overpayment'
);


##############################
# 2. Negative Balance Settings Are Unset, No Payment Made
##############################

### Setup use case variables
$xact_id = 2;
$item_id = 3;
$item_barcode = 'CONC4000038';
$org_id = 1; #CONS

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 2: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00'
);


##############################
# 3. Basic No Negative Balance Test
##############################

### Setup use case variables
$xact_id = 3;
$item_id = 4;
$item_barcode = 'CONC4000039';
$org_id = 1; #CONS

# Setup Org Unit Settings
$settings = {
    'bill.prohibit_negative_balance_default' => 1
};
$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 3: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (negative balance prohibited)'
);

##############################
# 4. Prohibit Negative Balances with Partial Payment
##############################

### Setup use case variables
$xact_id = 4;
$item_id = 5;
$item_barcode = 'CONC4000040';
$org_id = 1; #CONS

# Setup Org Unit Settings
# already set: 'bill.prohibit_negative_balance_default' => 1

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 4: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### confirm the copy is lost
$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

### partially pay the bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '10.00' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '40.00',
    'Remaining balance of 40.00 after payment'
);

### check-in the lost copy
$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (negative balance prohibited)'
);


###############################
## 11. Manually voiding lost book fee does not result in negative balances
###############################
#
#### Setup use case variables
#$xact_id = 5;
#$item_id = 6;
#$item_barcode = 'CONC4000040';
#$org_id = 1; #CONS
#
## Setup Org Unit Settings
## already set: 'bill.prohibit_negative_balance_default' => 1
#
#$summary = fetch_billable_xact_summary($xact_id);
#ok( $summary, 'CASE 11: Found the transaction summary');
#is(
#    $summary->balance_owed,
#    '50.00',
#    'Starting balance owed is 50.00 for lost item'
#);
#
#### confirm the copy is lost
#$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
#if (my $item_resp = $item_req->recv) {
#    if (my $item = $item_resp->content) {
#        is(
#            $item->status,
#            3,
#            'Item with id = ' . $item_id . ' has status of LOST'
#        );
#    }
#}
#
#### partially pay the bill
#$payment_blob = {
#    userid => $patron_id,
#    note => '09-lp1198465_neg_balances.t',
#    payment_type => 'cash_payment',
#    patron_credit => '0.00',
#    payments => [ [ $xact_id, '10.00' ] ]
#};
#$pay_resp = pay_bills($payment_blob);
#
#is(
#    scalar( @{ $pay_resp->{payments} } ),
#    1,
#    'Payment response included one payment id'
#);
#
#$summary = fetch_billable_xact_summary($xact_id);
#is(
#    $summary->balance_owed,
#    '40.00',
#    'Remaining balance of 40.00 after payment'
#);
#
#### TODO: manually void "the rest" of the bill (i.e. prevent neg bal)
#### XXX: HARDCODING billing id for now; should look up the LOST bill for this xact?
#my @billing_ids = (6);
#my $void_resp = void_bills(\@billing_ids);
#
#is(
#    $void_resp,
#    '1',
#    'Voiding was successful'
#);
#
#### verify ending state
#
#$summary = fetch_billable_xact_summary($xact_id);
#is(
#    $summary->balance_owed,
#    '0.00',
#    'Patron has a balance of 0.00 (negative balance prohibited)'
#);


##############################
# 12. Test negative balance settings on fines
##############################

# Setup next patron
$patron_id = 5;
$patron_usrname = '99999387993';

# Look up the patron
if ($user_obj = retrieve_patron($patron_id)) {
    is(
        ref $user_obj,
        'Fieldmapper::actor::user',
        'open-ils.storage.direct.actor.user.retrieve returned aou object'
    );
    is(
        $user_obj->usrname,
        $patron_usrname,
        'Patron with id = ' . $patron_id . ' has username ' . $patron_usrname
    );
}

### Setup use case variables
$xact_id = 7;
$item_id = 8;
$item_barcode = 'CONC4000043';
$org_id = 1; #CONS

# Setup Org Unit Settings
# already set: 'bill.prohibit_negative_balance_default' => 1

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 12: Found the transaction summary');
is(
    $summary->balance_owed,
    '0.70',
    'Starting balance owed is 0.70 for overdue fines'
);

### partially pay the bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '0.20' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.50',
    'Remaining balance of 0.50 after payment'
);

### Check in using Amnesty Mode
$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode,
    void_overdues => 1
});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state
$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (remaining fines forgiven)'
);


##############################
# 10. Interval Testing
##############################

# Setup Org Unit Settings
# already set: 'bill.prohibit_negative_balance_default' => 1

# Setup Org Unit Settings
$org_id = 1; #CONS
$settings = {
    'bill.negative_balance_interval_default' => '1 hour'
};

$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

### Setup use case variables
$xact_id = 8;
$item_id = 9;
$item_barcode = 'CONC4000044';

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 10.1: Found the transaction summary');
is(
    $summary->balance_owed,
    '0.00',
    'Starting balance owed is 0.00 (LOST fee paid)'
);

### Check in first item (right after its payment)
$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode,
});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state for 10.1
$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '-50.00',
    'Patron has a balance of -50.00 (lost item returned during interval)'
);

### Setup use case variables
$xact_id = 9;
$item_id = 10;
$item_barcode = 'CONC4000045';

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 10.2: Found the transaction summary');
is(
    $summary->balance_owed,
    '0.00',
    'Starting balance owed is 0.00 (LOST fee paid)'
);

### Check in second item (2 hours after its payment)
$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode,
});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state
$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '0.00',
    'Patron has a balance of 0.00 (lost item returned after interval)'
);


#############################
# 8. Restore Overdue Fines Appropriately, Previous Voids, Negative Balance Allowed
#############################

## TODO: consider using a later xact_id/item_id, instead of reverting back to user 4

# Setup first patron (again)
$patron_id = 4;
$patron_usrname = '99999355250';

# Look up the patron
if ($user_obj = retrieve_patron($patron_id)) {
    is(
        ref $user_obj,
        'Fieldmapper::actor::user',
        'open-ils.storage.direct.actor.user.retrieve returned aou object'
    );
    is(
        $user_obj->usrname,
        $patron_usrname,
        'Patron with id = ' . $patron_id . ' has username ' . $patron_usrname
    );
}

### Setup use case variables
$xact_id = 6;
$item_id = 7;
$item_barcode = 'CONC4000042';
$org_id = 1; #CONS

# Setup Org Unit Settings
$settings = {
    'bill.prohibit_negative_balance_default' => 0,
    'circ.restore_overdue_on_lost_return' => 1,
    'circ.lost.generate_overdue_on_checkin' => 1
};

$apputils->simplereq(
    'open-ils.actor',
    'open-ils.actor.org_unit.settings.update',
    $script->authtoken,
    $org_id,
    $settings
);

$summary = fetch_billable_xact_summary($xact_id);
ok( $summary, 'CASE 8: Found the transaction summary');
is(
    $summary->balance_owed,
    '50.00',
    'Starting balance owed is 50.00 for lost item'
);

### partially pay the bill
$payment_blob = {
    userid => $patron_id,
    note => '09-lp1198465_neg_balances.t',
    payment_type => 'cash_payment',
    patron_credit => '0.00',
    payments => [ [ $xact_id, '10.00' ] ]
};
$pay_resp = pay_bills($payment_blob);

is(
    scalar( @{ $pay_resp->{payments} } ),
    1,
    'Payment response included one payment id'
);

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '40.00',
    'Remaining balance of 40.00 after payment'
);

### check-in the lost copy

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        is(
            ref $item,
            'Fieldmapper::asset::copy',
            'open-ils.storage.direct.asset.copy.retrieve returned acp object'
        );
        is(
            $item->status,
            3,
            'Item with id = ' . $item_id . ' has status of LOST'
        );
    }
}

$checkin_resp = $script->do_checkin_override({
    barcode => $item_barcode});
is(
    $checkin_resp->{ilsevent},
    0,
    'Checkin returned a SUCCESS event'
);

$item_req = $storage_ses->request('open-ils.storage.direct.asset.copy.retrieve', $item_id);
if (my $item_resp = $item_req->recv) {
    if (my $item = $item_resp->content) {
        ok(
            $item->status == 7 || $item->status == 0,
            'Item with id = ' . $item_id . ' has status of Reshelving or Available after fresh Storage request'
        );
    }
}

### verify ending state

$summary = fetch_billable_xact_summary($xact_id);
is(
    $summary->balance_owed,
    '-7.00',
    'Patron has a negative balance of 7.00 due to overpayment'
);



$script->logout();

