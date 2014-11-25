/* ************************************************************************
 * Copyright (c) 2014 GMaxera <gmaxera@gmail.com>                         *
 *                                                                        *
 * This file is part of QtFacebook                                        *
 *                                                                        *
 * QtFacebook is free software: you can redistribute it and/or modify     *
 * it under the terms of the GNU General Public License as published by   *
 * the Free Software Foundation, either version 3 of the License, or      *
 * (at your option) any later version.                                    *
 *                                                                        *
 * This program is distributed in the hope that it will be useful,        *
 * but WITHOUT ANY WARRANTY; without even the implied warranty of         *
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                   *
 * See the GNU General Public License for more details.                   *
 *                                                                        *
 * You should have received a copy of the GNU General Public License      *
 * along with this program. If not, see <http://www.gnu.org/licenses/>.   *
 * ********************************************************************** */

#include "qfacebook.h"
#import "FacebookSDK/FacebookSDK.h"
#import "UIKit/UIKit.h"
#include <QString>

/*! Override the application:openURL UIApplicationDelegate adding
 *  a category to the QIOApplicationDelegate.
 *  The only way to do that even if it's a bit like hacking the Qt stuff
 *  See: https://bugreports.qt-project.org/browse/QTBUG-38184
 */
@interface QIOSApplicationDelegate
@end
//! Add a category to QIOSApplicationDelegate
@interface QIOSApplicationDelegate (QFacebookApplicationDelegate)
@end
//! Now add method for handling the openURL from Facebook Login
@implementation QIOSApplicationDelegate (QFacebookApplicationDelegate)
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString*) sourceApplication annotation:(id)annotation {
#pragma unused(application)
#pragma unused(sourceApplication)
#pragma unused(annotation)
	return [[FBSession activeSession] handleOpenURL:url];
}
@end

class QFacebookPlatformData {
public:
	QFacebook* qFacebook;
	void sessionStateHandler(FBSession*, FBSessionState fstate, NSError* error) {
		if (error) {
			NSLog(@"error:%@",error);
		}
		switch( fstate ) {
		case FBSessionStateCreated:
			qFacebook->state = QFacebook::SessionCreated;
			qFacebook->connected = false;
			break;
		case FBSessionStateCreatedTokenLoaded:
			qFacebook->state = QFacebook::SessionCreatedTokenLoaded;
			qFacebook->connected = false;
			break;
		case FBSessionStateCreatedOpening:
			qFacebook->state = QFacebook::SessionOpening;
			qFacebook->connected = false;
			break;
		case FBSessionStateOpen:
			qFacebook->state = QFacebook::SessionOpen;
			qFacebook->connected = true;
			break;
		case FBSessionStateOpenTokenExtended:
			qFacebook->state = QFacebook::SessionOpenTokenExtended;
			qFacebook->connected = true;
			break;
		case FBSessionStateClosedLoginFailed:
			qFacebook->state = QFacebook::SessionClosedLoginFailed;
			qFacebook->connected = false;
			break;
		case FBSessionStateClosed:
			qFacebook->state = QFacebook::SessionClosed;
			qFacebook->connected = false;
			break;
		}
		emit qFacebook->stateChanged( qFacebook->state );
		emit qFacebook->connectedChanged( qFacebook->connected );
	}
	//! subset of requestPermissions that only allow reading from Facebook
	NSMutableArray* readPermissions;
	//! subset of requestPermissions that allow writing to Facebook
	NSMutableArray* writePermissions;
};

void QFacebook::initPlatformData() {
	appID = QString::fromNSString( [FBSettings defaultAppID] );
	displayName = QString::fromNSString( [FBSettings defaultDisplayName] );
	data = new QFacebookPlatformData();
	data->qFacebook = this;
	data->readPermissions = [[NSMutableArray alloc] init];
	data->writePermissions = [[NSMutableArray alloc] init];
	[[FBSession activeSession]
			setStateChangeHandler:^(FBSession* session, FBSessionState state, NSError* error) {
				data->sessionStateHandler(session, state, error);
	}];
	data->sessionStateHandler( [FBSession activeSession], [[FBSession activeSession] state], NULL );
}

void QFacebook::login() {
	FBSession* fbSession = [[FBSession alloc] initWithPermissions:(data->readPermissions)];
	[fbSession setStateChangeHandler:^(FBSession* session, FBSessionState state, NSError* error) {
		data->sessionStateHandler(session, state, error);
	}];
	[FBSession setActiveSession:fbSession];
	// for forcing the in-app login using webview: FBSessionLoginBehaviorForcingWebView
	// default FBSessionLoginBehaviorWithFallbackToWebView
	[fbSession openWithBehavior:FBSessionLoginBehaviorWithFallbackToWebView completionHandler:nil];
}

void QFacebook::close() {
	[[FBSession activeSession] closeAndClearTokenInformation];
}

void QFacebook::setAppID( QString appID ) {
	if ( this->appID != appID ) {
		this->appID = appID;
		[FBSettings setDefaultAppID:(this->appID.toNSString())];
		emit appIDChanged( this->appID );
	}
}

void QFacebook::setDisplayName( QString displayName ) {
	if ( this->displayName != displayName ) {
		this->displayName = displayName;
		[FBSettings setDefaultDisplayName:(this->displayName.toNSString())];
		emit displayNameChanged( this->displayName );
	}
}

void QFacebook::setRequestPermissions( QStringList requestPermissions ) {
	this->requestPermissions = requestPermissions;
	[(data->readPermissions) removeAllObjects];
	[(data->writePermissions) removeAllObjects];
	foreach( QString permission, this->requestPermissions ) {
		if ( isReadPermission(permission) ) {
			[(data->readPermissions) addObject:permission.toNSString()];
		} else {
			[(data->writePermissions) addObject:permission.toNSString()];
		}
	}
	emit requestPermissionsChanged( this->requestPermissions );
}

void QFacebook::addRequestPermission( QString requestPermission ) {
	if ( !requestPermissions.contains(requestPermission) ) {
		// add the permission
		requestPermissions.append( requestPermission );
		if ( isReadPermission(requestPermission) ) {
			[(data->readPermissions) addObject:requestPermission.toNSString()];
		} else {
			[(data->writePermissions) addObject:requestPermission.toNSString()];
		}
		emit requestPermissionsChanged(requestPermissions);
	}
}

void QFacebook::onApplicationStateChanged(Qt::ApplicationState state) {
	if ( state == Qt::ApplicationActive ) {
		[[FBSession activeSession] handleDidBecomeActive];
	}
}
