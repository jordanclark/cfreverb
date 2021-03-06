component name="reverb" displayname="reverb API REST Wrapper v2" {
	// cfprocessingdirective( preserveCase=true );

	reverb function init(
		required string apiBearer
	,	string apiVersion= "3.0"
	,	string apiUrl= "https://api.reverb.com/api"
	,	string apiCurrency= "USD"
	,	string userAgent= "CFML API Agent 0.1"
	,	numeric throttle= 250
	,	numeric httpTimeOut= 60
	,	boolean debug
	) {
		arguments.debug = ( arguments.debug ?: request.debug ?: false );
		this.apiBearer= arguments.apiBearer;
		this.apiVersion= arguments.apiVersion;
		this.apiUrl= arguments.apiUrl;
		this.apiCurrency= arguments.apiCurrency;
		this.userAgent= arguments.userAgent;
		this.httpTimeOut= arguments.httpTimeOut;
		this.throttle= arguments.throttle;
		this.debug= arguments.debug;
		this.lastRequest= server.reverb_lastRequest ?: 0;
		this.orderStatusOptions= [
			'unpaid'
		,	'payment_pending'
		,	'pending_review'
		,	'blocked'
		,	'partially_paid'
		,	'paid'
		,	'shipped'
		,	'picked_up'
		,	'received'
		,	'refunded'
		,	'cancelled'
		];
		this.orderFilterOptions= [
			'all'
		,	'awaiting_shipment'
		,	'unpaid'
		];
		return this;
	}

	function debugLog(required input) {
		if ( structKeyExists( request, "log" ) && isCustomFunction( request.log ) ) {
			if ( isSimpleValue( arguments.input ) ) {
				request.log( "reverb: " & arguments.input );
			} else {
				request.log( "reverb: (complex type)" );
				request.log( arguments.input );
			}
		} else {
			var info= ( isSimpleValue( arguments.input ) ? arguments.input : serializeJson( arguments.input ) );
			cftrace(
				var= "info"
			,	category= "reverb"
			,	type= "information"
			);
		}
		return;
	}

	struct function apiRequest(required string api) {
		var http= {};
		var item= "";
		var out= {
			args= arguments
		,	success= false
		,	error= ""
		,	status= ""
		,	statusCode= 0
		,	response= ""
		,	verb= listFirst( arguments.api, " " )
		,	requestUrl= this.apiUrl
		,	data= {}
		,	delay= 0
		};
		out.requestUrl &= listRest( out.args.api, " " );
		structDelete( out.args, "api" );
		// replace {var} in url 
		for ( item in out.args ) {
			// strip NULL values 
			if ( isNull( out.args[ item ] ) ) {
				structDelete( out.args, item );
			} else if ( isSimpleValue( arguments[ item ] ) && arguments[ item ] == "null" ) {
				arguments[ item ]= javaCast( "null", 0 );
			} else if ( findNoCase( "{#item#}", out.requestUrl ) ) {
				out.requestUrl= replaceNoCase( out.requestUrl, "{#item#}", out.args[ item ], "all" );
				structDelete( out.args, item );
			}
		}
		if ( out.verb == "GET" ) {
			out.requestUrl &= this.structToQueryString( out.args, out.requestUrl, true );
		} else if ( !structIsEmpty( out.args ) ) {
			out.body= serializeJSON( out.args, false, false );
		}
		this.debugLog( "API: #uCase( out.verb )#: #out.requestUrl#" );
		if ( structKeyExists( out, "body" ) ) {
			this.debugLog( out.body );
		}
		// this.debugLog( out );
		// throttle requests by sleeping the thread to prevent overloading api
		if ( this.lastRequest > 0 && this.throttle > 0 ) {
			out.delay= this.throttle - ( getTickCount() - this.lastRequest );
			if ( out.delay > 0 ) {
				this.debugLog( "Pausing for #out.delay#/ms" );
				sleep( out.delay );
			}
		}
		cftimer( type="debug", label="reverb request" ) {
			cfhttp( result="http", method=out.verb, url=out.requestUrl, charset="UTF-8", throwOnError=false,
				userAgent=this.userAgent, timeOut=this.httpTimeOut ) {
				cfhttpparam( type="header", name="authorization", value="Bearer #this.apiBearer#" );
				cfhttpparam( type="header", name="content-type", value="application/hal+json" );
				cfhttpparam( type="header", name="accept", value="application/hal+json" );
				cfhttpparam( type="header", name="accept-version", value=this.apiVersion );
				cfhttpparam( type="header", name="x-display-currency", value=this.apiCurrency );
				if ( structKeyExists( out, "body" ) ) {
					cfhttpparam( type="body", value=out.body );
				}
			}
			if ( this.throttle > 0 ) {
				this.lastRequest= getTickCount();
				server.reverb_lastRequest= this.lastRequest;
			}
		}
		out.response= toString( http.fileContent );
		out.statusCode= http.responseHeader.Status_Code ?: 500;
		if ( left( out.statusCode, 1 ) == 4 || left( out.statusCode, 1 ) == 5 ) {
			out.success= false;
			out.error= "status code error: #out.statusCode#";
		} else if ( out.response == "Connection Timeout" || out.response == "Connection Failure" ) {
			out.error= out.response;
		} else if ( left( out.statusCode, 1 ) == 2 ) {
			out.success= true;
		}
		// parse response 
		try {
			out.data= deserializeJSON( out.response );
			if ( isStruct( out.data ) && structKeyExists( out.data, "error" ) ) {
				out.success= false;
				out.error= out.data.error;
			} else if ( isStruct( out.data ) && structKeyExists( out.data, "status" ) && out.data.status == 400 ) {
				out.success= false;
				out.error= out.data.detail;
			/*
			} else if( isStruct( out.data ) && structKeyExists( out.data, "message" ) && find( "already exists", out.data.message ) && out.statusCode IS 409 ) {
				out.success= true;
				out.error= "";
				out.data= out.data.message;
			*/
			}
		} catch (any cfcatch) {
			out.error= "JSON Error: " & (cfcatch.message?:"No catch message") & " " & (cfcatch.detail?:"No catch detail");
			this.debugLog( out.error );
		}
		if ( len( out.error ) ) {
			out.success= false;
		}
		this.debugLog( out.statusCode & " " & out.error );
		return out;
	}
	// ---------------------------------------------------------------------------- 
	// ITEMS 
	// ---------------------------------------------------------------------------- 
	
	// ---------------------------------------------------------------------------- 
	// MARKETPLACE 
	// ---------------------------------------------------------------------------- 

	struct function listOrders(string status= "all", numeric page= 1, numeric per_page= 50) {
		return this.apiRequest( api= "GET /my/orders/selling/{status}", argumentCollection= arguments );
	}

	struct function getOrder(required string id) {
		return this.apiRequest( api= "GET /my/orders/selling/{id}", argumentCollection= arguments );
	}

	struct function shipOrder(required string id, required string provider, required string tracking_number, boolean send_notification= true) {
		return this.apiRequest( api= "POST /my/orders/selling/{id}/ship", argumentCollection= arguments );
	}

	struct function getListing(required string id) {
		return this.apiRequest( api= "GET /listings/{id}", argumentCollection= arguments );
	}

	string function structToQueryString(required struct stInput, string sUrl= "", boolean bEncode= true) {
		var sOutput= "";
		var sItem= "";
		var sValue= "";
		var amp= ( find( "?", arguments.sUrl ) ? "&" : "?" );
		for ( sItem in stInput ) {
			sValue= stInput[ sItem ];
			if ( !isNull( sValue ) && len( sValue ) ) {
				if ( bEncode ) {
					sOutput &= amp & sItem & "=" & urlEncodedFormat( sValue );
				} else {
					sOutput &= amp & sItem & "=" & sValue;
				}
				amp= "&";
			}
		}
		return sOutput;
	}

}
