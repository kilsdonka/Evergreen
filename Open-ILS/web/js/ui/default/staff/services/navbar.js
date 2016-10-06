angular.module('egCoreMod')

.directive('egNavbar', function() {
    return {
        restrict : 'AE',
        transclude : true,
        templateUrl : 'eg-navbar-template',
        link : function(scope, element, attrs) {

            // Find all eg-accesskey entries within the menu and attach
            // hotkey handlers for each.  
            // jqlite doesn't support selectors, so we have to 
            // manually navigate to the elements we're interested in.
            function inspect(elm) {
                elm = angular.element(elm);
                if (elm.attr('eg-accesskey')) {
                    scope.addHotkey(
                        elm.attr('eg-accesskey'),
                        elm.attr('href'),
                        elm.attr('eg-accesskey-desc'),
                        elm
                    );
                }
                angular.forEach(elm.children(), inspect);
            }
            inspect(element);
        },

        controller:['$scope','$window','$location','$timeout','hotkeys','egCore','$uibModal','ngToast',
            function($scope , $window , $location , $timeout , hotkeys , egCore , $uibModal , ngToast) {

                function navTo(path) {                                           
                    // Strip the leading "./" if any.
                    path = path.replace(/^\.\//,'');
                    var reg = new RegExp($location.path());
                    $window.location.href = egCore.env.basePath + path;
                }       

                // adds a keyboard shortcut
                // http://chieffancypants.github.io/angular-hotkeys/
                $scope.addHotkey = function(key, path, desc, elm) {                 
                    hotkeys.add({
                        combo: key,
                        allowIn: ['INPUT','SELECT','TEXTAREA'],
                        description: desc,
                        callback: function(e) {
                            e.preventDefault();
                            if (path) return navTo(path);
                            return $timeout(function(){$(elm).trigger('click')});
                        }
                    });
                };

                $scope.retrieveLastRecord = function() {
                    var last_record = egCore.hatch.getLocalItem("eg.cat.last_record_retrieved");
                    if (last_record) {
                        $window.location.href =
                            egCore.env.basePath + 'cat/catalog/record/' + last_record;
                    }
                }

                $scope.applyLocale = function(locale) {
                    // EGWeb.pm can change the locale for us w/ the right param
                    // Note: avoid using $location.search() to derive a new
                    // URL, since it creates an intermediate path change.
                    // Instead, use the ham-fisted approach of killing any
                    // search args and applying the args we want.
                    $window.location.href = 
                        $window.location.href.replace(
                            /(\?|\&).*/,
                            '?set_eg_locale=' + encodeURIComponent(locale)
                        );
                }

                $scope.changeOperatorUndo = function() {
                        egCore.auth.opChangeUndo();
                        $scope.op_changed = false;
                        ngToast.create(egCore.strings.OP_CHANGE_SUCCESS);
                }

                $scope.changeOperator = function() {
                    $uibModal.open({
                        templateUrl: './share/t_opchange',
                        controller:
                            ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                            $scope.args = {username : '', password : ''};
                            $scope.focus = true;
                            $scope.ok = function() { $uibModalInstance.close($scope.args) }
                            $scope.cancel = function () { $uibModalInstance.dismiss() }
                        }]
                    }).result.then(function (args) {
                        if (!args || !args.username || !args.password) return;
                        args.workstation = egCore.auth.workstation();
                        egCore.auth.opChange(args).then(
                            function() {
                                console.log('op change success');
                                $scope.op_changed = true;
                                ngToast.create(egCore.strings.OP_CHANGE_SUCCESS);
                            }, // note success with toast?
                            function() {
                                console.log('op change failure');
                                ngToast.warning(egCore.strings.OP_CHANGE_FAILURE);
                            }  // note failure with toast?
                        );
                    });
                }

                $scope.currentToken = function () {
                    return egCore.auth.token();
                }

                // tied to logout link
                $scope.logout = function() {
                    egCore.auth.logout();
                    return true;
                };

                egCore.startup.go().then(
                    function() {
                        if (egCore.auth.user()) {
                            $scope.op_changed = egCore.auth.OCtoken() ? true : false;
                            $scope.username = egCore.auth.user().usrname();
                            $scope.workstation = egCore.auth.workstation();
                        }
                    }
                );
            }
        ]
    }
});
 
