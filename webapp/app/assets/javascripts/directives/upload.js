angular.module('app.directives')
    .directive('uploadSubmit', ['$parse', 'flash', function($parse, flash) {
        // Utility function to get the closest parent element with a given tag
        function getParentNodeByTagName(element, tagName) {
            element = angular.element(element);
            var parent = element.parent();
            tagName = tagName.toLowerCase();

            if ( parent && parent[0].tagName.toLowerCase() === tagName ) {
                return parent;
            } else {
                return !parent ? null : getParentNodeByTagName(parent, tagName);
            }
        }

        return {
            restrict: 'AC',
            link: function(scope, element, attrs) {
                // Options (just 1 for now)
                // Each option should be prefixed with 'upload-options-' or 'uploadOptions'
                // {
                //    // specify whether to enable the submit button when uploading forms
                //    enableControls: bool
                //
                //    // sets the value of hidden input to their ng-model when the form is submitted
                //    convertHidden
                // }
                var options = {};
                options.enableControls = attrs.uploadOptionsEnableControls;

                if ( attrs.hasOwnProperty( "uploadOptionsConvertHidden" ) ) {
                    // Allow blank or true
                    options.convertHidden = attrs.uploadOptionsConvertHidden != "false";
                }

                // submit the form
                var form = getParentNodeByTagName(element, 'form');

                // Retrieve the callback function
                var fn = $parse(attrs.uploadSubmit);

                if (!angular.isFunction(fn)) {
                    var message = "The expression on the ngUpload directive does not point to a valid function.";
                    throw message + "\n";
                }

                element.bind('click', function($event) {
                    // prevent default behavior of click
                    if ($event) {
                        $event.preventDefault = true;
                    }

                    if (element.attr('disabled')) {
                        return;
                    }

                    // create a new iframe
                    var iframe = angular.element("<iframe id='upload_iframe' name='upload_iframe' border='0' width='0' height='0' style='width: 0px; height: 0px; border: none; display: none' />");

                    // add the new iframe to application
                    form.parent().append(iframe);

                    // attach function to load event of the iframe
                    iframe.bind('load', function () {
                        // get content using native DOM. use of jQuery to retrieve content triggers IE bug
                        // http://bugs.jquery.com/ticket/13936
                        var nativeIframe = iframe[0];
                        var iFrameDoc = nativeIframe.contentDocument || nativeIframe.contentWindow.document;
                        var content = iFrameDoc.body.innerHTML;
                        try {
                            content = JSON.parse(content);
                        } catch (e) {
                            if (content.indexOf('allowed types: jpg, jpeg, png') != -1) {
                              flash.error('Allowed types to upload: jpg, jpeg, png');
                            };
                            if (console) { console.log('WARN: XHR response is not valid json'); }
                        }
                        // if outside a digest cycle, execute the upload response function in the active scope
                        // else execute the upload response function in the current digest
                        if (!scope.$$phase) {
                            scope.$apply(function () {
                                fn(scope, { content: content, completed: true });
                            });
                        } else {
                            fn(scope, { content: content, completed: true });
                        }
                        // remove iframe
                        if (content !== "") { // Fixes a bug in Google Chrome that dispose the iframe before content is ready.
                            setTimeout(function () { iframe.remove(); }, 250);
                        }
                        element.attr('disabled', null);
                        element.attr('title', 'Click to start upload.');
                    });

                    if (!scope.$$phase) {
                        scope.$apply(function () {
                            fn(scope, {content: "Please wait...", completed: false });
                        });
                    } else {
                        fn(scope, {content: "Please wait...", completed: false });
                    }

                    var enabled = true;
                    if (!options.enableControls) {
                        // disable the submit control on click
                        element.attr('disabled', 'disabled');
                        enabled = false;
                    }
                    // why do we need this???
                    element.attr('title', (enabled ? '[ENABLED]: ' : '[DISABLED]: ') + 'Uploading, please wait...');

                    // If convertHidden option is enabled, set the value of hidden fields to the eval of the ng-model
                    if (options.convertHidden) {
                        angular.forEach(form.find('input'), function(element) {
                            element = angular.element(element);
                            if (element.attr('ng-model') &&
                                element.attr('type') &&
                                element.attr('type') == 'hidden') {
                                element.attr('value', scope.$eval(element.attr('ng-model')));
                            }
                        });
                    }

                    form[0].submit();

                }).attr('title', 'Click to start upload.');
            }
        };
    }]);
angular.module('app.directives')
    .directive('ngUpload', ['$parse', '$document', function ($parse, $document) {
        // Utility function to get meta tag with a given name attribute
        function getMetaTagWithName(name) {
            var head = $document.find('head');
            var match;

            angular.forEach(head.find('meta'), function(element) {
                if ( element.getAttribute('name') === name ) {
                    match = element;
                }
            });

            return angular.element(match);
        }

        return {
            restrict: 'AC',
            link: function (scope, element, attrs) {

                // Options (just 1 for now)
                // Each option should be prefixed with 'upload-options-' or 'uploadOptions'
                // {
                //    // add the Rails CSRF hidden input to form
                //    enableRailsCsrf: bool
                // }

                var options = {};
                if ( attrs.hasOwnProperty( "uploadOptionsEnableRailsCsrf" ) ) {
                    // allow for blank or true
                    options.enableRailsCsrf = attrs.uploadOptionsEnableRailsCsrf != "false";
                }

                element.attr("target", "upload_iframe");
                element.attr("method", "post");
                // Append a timestamp field to the url to prevent browser caching results
                var separator = element.attr("action").indexOf('?')==-1 ? '?' : '&';
                element.attr("action", element.attr("action") + separator + "_t=" + new Date().getTime());
                element.attr("enctype", "multipart/form-data");
                element.attr("encoding", "multipart/form-data");

                // If enabled, add csrf hidden input to form
                if ( options.enableRailsCsrf ) {
                    var input = angular.element("<input />");
                        input.attr("class", "upload-csrf-token");
                        input.attr("type", "hidden");
                        input.attr("name", getMetaTagWithName('csrf-param').attr('content'));
                        input.val(getMetaTagWithName('csrf-token').attr('content'));

                    element.append(input);
                }
            }
        };
    }]);