/* ---------------------------------------------------------------------------
 * Copyright (C) 2008  Georgia Public Library Service
 * Bill Erickson <erickson@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * ---------------------------------------------------------------------------
 */

if(!dojo._hasResource['openils.acq.Fund']) {
dojo._hasResource['openils.acq.Fund'] = true;
dojo.provide('openils.acq.Fund');
dojo.require('fieldmapper.Fieldmapper');

/** Declare the Fund class with dojo */
dojo.declare('openils.acq.Fund', null, {
    /* add instance methods here if necessary */
});

openils.acq.Fund.cache = {};

openils.acq.Fund.createStore = function(onComplete) {
    /** Fetches the list of funding_sources and builds a grid from them */

    function mkStore(r) {
        var msg;
        var items = [];
        while(msg = r.recv()) {
            var src = msg.content();
            openils.acq.Fund.cache[src.id()] = src;
            items.push(src);
            console.log('loaded fund: ' + src.name());
        }
        console.log(js2JSON(acqf.toStoreData(items)));
        onComplete(acqf.toStoreData(items));
    }

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund.org.retrieve'],
        {   async: true,
            params: [openils.User.authtoken, null, {flesh_summary:1}],
            oncomplete: mkStore
        }
    );
};

/**
 * Create a new fund
 * @param fields Key/value pairs used to create the new fund
 */
openils.acq.Fund.create = function(fields, onCreateComplete) {

    var fund = new acqf()
    for(var field in fields) 
        fund[field](fields[field]);

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.fund.create'],
        {   async: true,
            params: [openils.User.authtoken, fund],
            oncomplete: function(r) {
                var msg = r.recv();
                var id = msg.content();
                if(onCreateComplete)
                    onCreateComplete(id);
            }
        }
    );
};

}

