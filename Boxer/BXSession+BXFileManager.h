/* 
 Boxer is copyright 2009 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/GNU General Public License.txt, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


//The BXFileManager category extends BXSession with methods specifically for controlling the
//DOS filesystem and for responding to relevant changes in the OS X filesystem.

#import <Cocoa/Cocoa.h>
#import "BXSession.h"

@class BXDrive;

@interface BXSession (BXFileManager)

//Class methods concerning files
//------------------------------


//UTI filetypes that should be given their own drives, even if they are already accessible within an existing DOS drive.
//This is used by shouldMountDriveForPath: to allow disc images or drive folders inside a gamebox to be mounted as
//separate drives even when their containing gamebox is already mounted.
+ (NSArray *) separatelyMountedTypes;

//Returns whether the specified OS X path represents a DOS/Windows executable.
+ (BOOL) isExecutable: (NSString *)path;


//File and folder mounting
//------------------------

//Tells the emulator to flush its DOS drive caches to reflect changes in the OS X filesystem.
//No longer used, since we explicitly listen for changes to the underlying filesystem and do this automatically.
- (IBAction) refreshFolders:	(id)sender;

//Display the mount-a-new-drive sheet in this session's window.
- (IBAction) showMountPanel:	(id)sender;

//Open the represented object of the sender in DOS.
- (IBAction) openInDOS:			(id)sender;

//Unmount the represented object of the sender (assumed to be a BXDrive). 
- (IBAction) unmountDrive:		(id)sender;


//Returns an array of currently-mounted drives, filtered to exclude internal and hidden drives.
//Used only by UIs, and so really belongs downstream in UI controllers instead.
- (NSArray *) drives;

//Returns whether the specified path should be mounted as a new drive.
//Returns YES if the path isn't already DOS-accessible or deserves its own drive anyway, NO otherwise.
- (BOOL) shouldMountDriveForPath: (NSString *)path;

//Adds a new drive to expose the specified path, using preferredMountPointForPath:preferringImages:
//to choose an appropriate base location for the drive.
- (BXDrive *) mountDriveForPath: (NSString *)path;

//Open the file at the specified path in DOS.
//If path is an executable, it will be launched; otherwise, we'll just change the working directory to it.
- (BOOL) openFileAtPath: (NSString *)path;

//Returns the most appropriate base location for a drive to expose the specified path:
//If path points to a disc image, that will be the mount point.
//If path is on a CD, then the CD's root folder will be the mount point.
//Otherwise, the parent folder of the item (or the item itself, if it is a folder) will be the mount point.

//If useSourceImage is YES, then this will return any backing disc image for the specified path. 
//NOTE: This option should not yet be used, as the drive management does not track both 
- (NSString *) preferredMountPointForPath: (NSString *)path;


//Automount all ISO9660 CD-ROM volumes that are currently mounted in OS X.
//Will not create new mounts for ones that are already mounted.
//Returns YES if any new volumes were created, NO otherwise.
- (BOOL) mountCDVolumes;

//Unmount the BXDrives in the specified array.
- (BOOL) unmountDrives: (NSArray *)drives;

@end



//The methods in this category are not intended to be called outside BXSession.
@interface BXSession (BXFileManagerInternals)


//Handling filesystem notifications
//---------------------------------

- (void) _registerForFilesystemNotifications;
- (void) _deregisterForFilesystemNotifications;

- (void) _volumeDidUnmount:		(NSNotification *)theNotification;
- (void) _volumeDidMount:		(NSNotification *)theNotification;
- (void) _filesystemDidChange:	(NSNotification *)theNotification;

- (void) _DOSDriveDidMount:		(NSNotification *)theNotification;
- (void) _DOSDriveDidUnmount:	(NSNotification *)theNotification;

- (void) _startTrackingChangesAtPath:	(NSString *)path;
- (void) _stopTrackingChangesAtPath:	(NSString *)path;

@end