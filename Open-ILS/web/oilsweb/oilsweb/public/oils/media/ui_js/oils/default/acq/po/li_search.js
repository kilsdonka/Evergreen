dojo.require('fieldmapper.Fieldmapper');
dojo.require('dijit.ProgressBar');
dojo.require('dijit.form.Form');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.Button');
dojo.require("dijit.Dialog");
dojo.require('openils.Event');
dojo.require('openils.acq.Lineitems');
dojo.require('openils.acq.Provider');
dojo.require('openils.acq.PO');
dojo.require('openils.widget.OrgUnitFilteringSelect');

var recvCount = 0;
var user = new openils.User();

var lineitems = [];

function drawForm() {
    buildProviderSelect(providerSelector);
}

function buildProviderSelect(sel, oncomplete) {
    openils.acq.Provider.createStore(
        function(store) {
            sel.store = new dojo.data.ItemFileReadStore({data:store});
            if(oncomplete)
                oncomplete();
        },
        'MANAGE_PROVIDER'
    );
}

var liReceived;
function doSearch(values) {
    var search = {};
    for(var v in values) {
        var val = values[v];
        if(val != null && val != '')
            search[v] = val;
    }

    //search = [search, {limit:searchLimit, offset:searchOffset}];
    search = [search, {}];
    options = {clear_marc:1, flesh_attrs:1};

    liReceived = 0;
    lineitems = [];
    dojo.style('searchProgress', 'visibility', 'visible');
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem.search'],
        {   async: true,
            params: [user.authtoken, search, options],
            onresponse: handleResult,
            oncomplete: viewList
        }
    );
}

function handleResult(r) {
    var result = r.recv().content();
    searchProgress.update({maximum: searchLimit, progress: ++liReceived});
    lineitems.push(result);
}

function viewList() {
    dojo.style('searchProgress', 'visibility', 'hidden');
    dojo.style('oils-acq-li-search-result-grid', 'visibility', 'visible');
    var store = new dojo.data.ItemFileReadStore({data:jub.toStoreData(lineitems)});
    var model = new dojox.grid.data.DojoData(
        null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
    JUBGrid.populate(liGrid, model, lineitems)
}

function createPOFromLineitems() {
    var po = new acqpo()
    po.provider(newPOProviderSelector.getValue());
    openils.acq.PO.create(po, 
        function(poId) {
            updateLiList(poId);
        }
    );
}

function updateLiList(poId) {
    _updateLiList(poId, 0);
}

function _updateLiList(poId, idx) {
    if(idx >= lineitems.length)
        return location.href = 'view/' + poId;
    var li = lineitems[idx];
    li.purchase_order(poId);
    new openils.acq.Lineitems({lineitem:li}).update(
        function(stat) {
            _updateLiList(poId, ++idx);
        }
    );
}
    

dojo.addOnLoad(drawForm);
