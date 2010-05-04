/* 
 Boxer is copyright 2009 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/GNU General Public License.txt, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import "BXSessionWindowController.h"
#import "BXSessionWindowController+BXRenderController.h"
#import "BXSessionWindow.h"
#import "BXAppController.h"
#import "BXProgramPanelController.h"

#import "BXEmulator+BXDOSFileSystem.h"
#import "BXEmulator+BXRendering.h"

#import "BXCloseAlert.h"
#import "BXSession+BXDragDrop.h"


@implementation BXSessionWindowController
@synthesize renderView, renderContainer, statusBar, programPanel;
@synthesize programPanelController;
@synthesize resizingProgrammatically;
@synthesize emulator;
@synthesize hiddenCursor, mouseActive, mouseLocked;


//Overridden to make the types explicit, so we don't have to keep casting the return values to avoid compilation warnings
- (BXSession *) document		{ return (BXSession *)[super document]; }
- (BXSessionWindow *) window	{ return (BXSessionWindow *)[super window]; }


//Initialisation and cleanup functions
//------------------------------------

- (void) dealloc
{
	[self removeObserver: self forKeyPath: @"document.activeProgramPath"];
	[[NSNotificationCenter defaultCenter] removeObserver: self];
	
	[self setRenderContainer: nil],			[renderContainer release];
	[self setRenderView: nil],				[renderView release];
	[self setStatusBar: nil],				[statusBar release];
	[self setProgramPanel: nil],			[programPanel release];
	[self setProgramPanelController: nil],	[programPanelController release];
	[self setHiddenCursor: nil],			[hiddenCursor release];

	[super dealloc];
}

- (void) awakeFromNib
{
	NSNotificationCenter *center	= [NSNotificationCenter defaultCenter];
	BXSessionWindow *theWindow		= [self window];
	
	//Add our view controllers into the responder chain
	[self setNextResponder: programPanelController];
	
	//Set up observing for UI events
	//------------------------------
	
	//These are handled by BoxerRenderController, our category for rendering-related delegate tasks
	[center addObserver:	self
			selector:		@selector(windowWillLiveResize:)
			name:			@"BXRenderViewWillLiveResizeNotification"
			object:			renderView];
	[center addObserver:	self
			selector:		@selector(windowDidLiveResize:)
			name:			@"BXRenderViewDidLiveResizeNotification"
			object:			renderView];
	[center addObserver:	self
			selector:		@selector(menuDidOpen:)
			name:			NSMenuDidBeginTrackingNotification
			object:			nil];
	[center addObserver:	self
			selector:		@selector(menuDidClose:)
			name:			NSMenuDidEndTrackingNotification
			object:			nil];
	
	//While we're here, register for drag-drop file operations (used for mounting folders and such)
	[theWindow registerForDraggedTypes: [NSArray arrayWithObjects: NSFilenamesPboardType, NSStringPboardType, nil]];
	
	
	//Set up the window UI components appropriately
	//---------------------------------------------
	
	//Show/hide the statusbar based on user's preference
	[self setStatusBarShown: [[NSUserDefaults standardUserDefaults] boolForKey: @"statusBarShown"]];
	
	//Hide the program panel by default - our parent session decides when it's appropriate to display this
	[self setProgramPanelShown: NO];
	
	//Apply a border to the window matching the size of the statusbar
	CGFloat borderThickness = [statusBar frame].size.height;
	[theWindow setContentBorderThickness: borderThickness forEdge: NSMinYEdge];
	
	
	//Set window rendering behaviour
	//------------------------------
	
	//Fix the window in the aspect ratio it will start up in
	[theWindow setContentAspectRatio: [self windowedRenderViewSize]];
	
	//Needed so that the window catches mouse movement over it
	[theWindow setAcceptsMouseMovedEvents: YES];
	
	//We don't support content-preservation yet, so disable the check to be slightly more efficient
	[theWindow setPreservesContentDuringLiveResize: NO];
	
	
	//Bindings galore
	//---------------
	 
	[self addObserver: self forKeyPath: @"document.activeProgramPath" options: 0 context: nil];
	
	[self bind: @"emulator" toObject: self withKeyPath: @"document.emulator" options: nil];
	
	[programPanelController bind: @"representedObject" toObject: self withKeyPath: @"document" options: nil];

	
	//Set up cursor region for mouse handling
	//---------------------------------------
	
	NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited | NSTrackingCursorUpdate | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect | NSTrackingAssumeInside;
	
	NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect: NSZeroRect
																options: options
																  owner: self
															   userInfo: nil];
	[renderView addTrackingArea: trackingArea];
	[trackingArea release];
}

- (void) setDocument: (BXSession *)theSession
{	
	[super setDocument: theSession];
	
	if (theSession)
	{
		id theWindow = [self window];

		//Now that we can retrieve the game's identifier from the session, use the autosaved window size for that game
		if ([theSession isGamePackage])
		{
			if ([theWindow setFrameAutosaveName: [theSession uniqueIdentifier]]) [theWindow center];
			//I hate to have to force the window to be centered but it compensates for Cocoa screwing up the position when it resizes a window from its saved frame: Cocoa pegs the window to the bottom-left origin when resizing this way, rather than the top-left as it should.
			//This comes up with non-16:10 games, since they get resized to match the 16:10 DOS ratio when they load. They would otherwise make the window travel down the screen each time they start up.
		}
		else
		{
			[theWindow setFrameAutosaveName: @"DOSWindow"];
		}
	}
}


- (void) setEmulator: (BXEmulator *)newEmulator 
{
	[self willChangeValueForKey: @"emulator"];
	
	BXEmulator *oldEmulator = [self emulator];
	if (![oldEmulator isEqualTo: newEmulator])
	{
		[oldEmulator unbind: @"mouseLocked"];
		[oldEmulator unbind: @"fullScreen"];
		[oldEmulator unbind: @"aspectCorrected"];
		[oldEmulator unbind: @"filterType"];
		[renderView unbind: @"renderer"];
		[self unbind: @"mouseActive"];
		
		[oldEmulator autorelease];
		emulator = [newEmulator retain];
		
		if (newEmulator)
		{
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			
			[newEmulator bind: @"filterType"
				  toObject: defaults
			   withKeyPath: @"filterType"
				   options: nil];
			
			[newEmulator bind: @"aspectCorrected"
				  toObject: defaults
			   withKeyPath: @"aspectCorrected"
				   options: nil];
			
			[newEmulator bind: @"fullScreen"
				  toObject: self
			   withKeyPath: @"fullScreen"
				   options: nil];
			
			[newEmulator bind: @"mouseLocked"
				  toObject: self
			   withKeyPath: @"mouseLocked"
				   options: nil];
			
			//Bind our render view to the emulator's BXRenderer instance
			[renderView bind: @"renderer"
					toObject: newEmulator
				 withKeyPath: @"renderer"
					 options: nil];
			
			[self bind: @"mouseActive"
			  toObject: newEmulator
		   withKeyPath: @"mouseActive"
			   options: nil];
		}
	}
	
	[self didChangeValueForKey: @"emulator"];
}


//Controlling the window title
//----------------------------

- (void) synchronizeWindowTitleWithDocumentName
{
	if ([[self document] isGamePackage])
	{
		//If the session is a gamebox, always use the gamebox for the window title (like a regular NSDocument.)
		return [super synchronizeWindowTitleWithDocumentName];
	}
	else
	{
		//If the session isn't a gamebox, then use the currently-active program as the window title.
		NSString *representedPath = [[self document] activeProgramPath];
		
		//If no program is running, then use the local filesystem equivalent of the current directory in DOS.
		if (!representedPath) representedPath = [[[self document] emulator] pathOfCurrentWorkingDirectory];
		
		if (representedPath) [[self window] setTitleWithRepresentedFilename: representedPath];
		else
		{
			//If that wasn't available either (e.g. we're on drive Z) then just display a generic title
			[[self window] setRepresentedFilename: @""];
			[[self window] setTitle: NSLocalizedString(
				@"MS-DOS Prompt", @"The standard window title when the session is at the DOS prompt.")];
		}
	}
}

- (void) observeValueForKeyPath: (NSString *)keyPath
						ofObject: (id)object
						  change: (NSDictionary *)change
						 context: (void *)context
{
	//Whenever the active program path changes, synchronise the window title and the unsaved changes indicator
	if ([keyPath isEqualToString: @"document.activeProgramPath"])
	{
		[self synchronizeWindowTitleWithDocumentName];
		
		//Flag the window as unsaved if pressing the close button would trigger a confirmation panel.
		//This matches the behaviour of the OS X Terminal.
		//Disabled as it also fades out the document icon, which is stretching the dubious
		//justification for using this feature to breaking point.
		
		//[self setDocumentEdited: [self shouldConfirmClose]];
	}
}


//Toggling window UI components
//-----------------------------

- (BOOL) statusBarShown		{ return ![statusBar isHidden]; }
- (BOOL) programPanelShown	{ return ![programPanel isHidden]; }

- (void) setStatusBarShown: (BOOL)show
{
	if (show != [self statusBarShown])
	{
		BXSessionWindow *theWindow	= [self window];
		
		//temporarily override the other views' resizing behaviour so that they don't slide up as we do this
		NSUInteger oldContainerMask		= [renderContainer autoresizingMask];
		NSUInteger oldProgramPanelMask	= [programPanel autoresizingMask];
		[renderContainer	setAutoresizingMask: NSViewMinYMargin];
		[programPanel		setAutoresizingMask: NSViewMinYMargin];
		
		//toggle the resize indicator on/off also (it doesn't play nice with the program panel)
		if (!show)	[theWindow setShowsResizeIndicator: NO];
		[self _slideView: statusBar shown: show];
		if (show)	[theWindow setShowsResizeIndicator: YES];
		
		[renderContainer	setAutoresizingMask: oldContainerMask];
		[programPanel		setAutoresizingMask: oldProgramPanelMask];
		
		//record the current statusbar state in the user defaults
		[[NSUserDefaults standardUserDefaults] setBool: show forKey: @"statusBarShown"];
	}
}

- (void) setProgramPanelShown: (BOOL)show
{
	//Don't open the program panel if we're not running a gamebox
	if (show && ![[self document] isGamePackage]) return;
	
	if (show != [self programPanelShown])
	{
		//temporarily override the other views' resizing behaviour so that they don't slide up as we do this
		NSUInteger oldMask = [renderContainer autoresizingMask];
		[renderContainer setAutoresizingMask: NSViewMinYMargin];
		
		[self _slideView: programPanel shown: show];
		
		[renderContainer setAutoresizingMask: oldMask];
	}
}


//Responding to interface actions
//-------------------------------

- (IBAction) toggleStatusBarShown:		(id)sender	{ [self setStatusBarShown:		![self statusBarShown]]; }
- (IBAction) toggleProgramPanelShown:	(id)sender	{ [self setProgramPanelShown:	![self programPanelShown]]; }

- (IBAction) exitFullScreen: (id)sender
{
	[self setFullScreenWithZoom: NO];
}

- (IBAction) toggleFullScreen: (id)sender
{
	BOOL enterFullScreen;
	
	if ([sender respondsToSelector: @selector(boolValue)])	enterFullScreen = [sender boolValue];
	else													enterFullScreen = ![self isFullScreen];
	
	[self setFullScreen: enterFullScreen];
}

- (IBAction) toggleFullScreenWithZoom: (id)sender
{
	BOOL enterFullScreen;
	
	if ([sender respondsToSelector: @selector(boolValue)])	enterFullScreen = [sender boolValue];
	else													enterFullScreen = ![self isFullScreen];
																		
	[self setFullScreenWithZoom: enterFullScreen];
}

//Toggle the emulator's active rendering filter. This will resize the window to fit, if the
//filter demands a minimum size smaller than the current window size.
- (IBAction) toggleFilterType: (id)sender
{
	NSInteger filterType = [sender tag];
	[[NSUserDefaults standardUserDefaults] setInteger: filterType forKey: @"filterType"];
}

- (IBAction) toggleMouseLocked: (id)sender
{
	BOOL wasLocked = [self mouseLocked];
	[self setMouseLocked: !wasLocked];
	
	//If the mouse state was actually toggled, play a sound to commemorate the occasion
	if ([self mouseLocked] != wasLocked)
	{
		NSString *lockSoundName	= (wasLocked) ? @"LockOpening" : @"LockClosing";
		[[NSApp delegate] playUISoundWithName: lockSoundName atVolume: 0.5f];
	}
}


- (BOOL) validateMenuItem: (NSMenuItem *)theItem
{	
	SEL theAction = [theItem action];
	NSString *title;

	if (theAction == @selector(toggleMouseLocked:))
	{
		[theItem setState: [self mouseLocked]];
		return [self mouseActive];
	}
	else if (theAction == @selector(toggleFilterType:))
	{
		NSInteger itemState;
		BXFilterType filterType	= [theItem tag];
		
		//Update the option state to reflect the current filter selection
		//If the filter is selected but not active at the current window size, we indicate this with a mixed state
		if		(filterType != [[self emulator] filterType])	itemState = NSOffState;
		else if	([[self emulator] filterIsActive])				itemState = NSOnState;
		else													itemState = NSMixedState;
		
		[theItem setState: itemState];
		
		return ([[self emulator] isExecuting]);
	}
	
	else if (theAction == @selector(toggleProgramPanelShown:))
	{
		if (![self programPanelShown])
			title = NSLocalizedString(@"Show Programs Panel", @"View menu option for showing the program panel.");
		else
			title = NSLocalizedString(@"Hide Programs Panel", @"View menu option for hiding the program panel.");
		
		[theItem setTitle: title];
	
		return [[self document] isGamePackage];
	}
	
	else if (theAction == @selector(toggleStatusBarShown:))
	{
		if (![self statusBarShown])
			title = NSLocalizedString(@"Show Status Bar", @"View menu option for showing the status bar.");
		else
			title = NSLocalizedString(@"Hide Status Bar", @"View menu option for hiding the status bar.");
		
		[theItem setTitle: title];
	
		return YES;
	}
	
    return YES;
}


//Handling drag-drop
//------------------

- (NSDragOperation)draggingEntered: (id <NSDraggingInfo>)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];	
	if ([[pboard types] containsObject: NSFilenamesPboardType])
	{
		NSArray *filePaths = [pboard propertyListForType: NSFilenamesPboardType];
		return [[self document] responseToDroppedFiles: filePaths];
	}
	else if ([[pboard types] containsObject: NSStringPboardType])
	{
		NSString *droppedString = [pboard stringForType: NSStringPboardType];
		return [[self document] responseToDroppedString: droppedString];
    }
	else return NSDragOperationNone;
}

- (BOOL)performDragOperation: (id <NSDraggingInfo>)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
 
    if ([[pboard types] containsObject: NSFilenamesPboardType])
	{
        NSArray *filePaths = [pboard propertyListForType: NSFilenamesPboardType];
		return [[self document] handleDroppedFiles: filePaths withLaunching: YES];
	}
	
	else if ([[pboard types] containsObject: NSStringPboardType])
	{
		NSString *droppedString = [pboard stringForType: NSStringPboardType];
		return [[self document] handleDroppedString: droppedString];
    }
	return NO;
}

//Handling window close
//---------------------

- (BOOL) shouldConfirmClose
{
	return (![[NSUserDefaults standardUserDefaults] boolForKey: @"suppressCloseAlert"] && [[self emulator] isRunningProcess]);
}

- (BOOL) windowShouldClose: (id)theWindow
{
	if ([self shouldConfirmClose])
	{
		BXCloseAlert *closeAlert = [BXCloseAlert closeAlertWhileSessionIsActive: [self document]];
		[closeAlert beginSheetModalForWindow: [self window]];
		return NO;
	}
	else return YES;
}

//Prompt to close the window, after exiting a game or program.
- (IBAction) windowShouldCloseAfterProgramCompletion: (id)sender
{
	BXCloseAlert *closeAlert = [BXCloseAlert closeAlertAfterSessionExited: [self document]];
	[closeAlert beginSheetModalForWindow: [self window]];
}

- (void) windowWillClose:(NSNotification *)notification
{
	//Make sure to tear down the fullscreen context before quitting
	[self exitFullScreen: self];
}
@end