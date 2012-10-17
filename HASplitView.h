//
//  HASplitView.h
//  Photographer
//
//  Created by Ben Uri on 7/6/12.
//  Copyright (c) 2012 Ben Uri. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AppKit/AppKit.h>

@interface HASplitView : NSView
{
  NSLayoutConstraint* _draggingConstraint;
  NSPoint _mouseDownLocation;
  CGFloat _draggingConstraintConstantAtMouseDown;
  BOOL _isVertical;
}

- (void)toggleSubviewShown:(NSView*)subview;
- (void)collapseSubview:(NSView*)subview;
- (void)uncollapseSubview:(NSView*)subview;
@property NSSplitViewDividerStyle dividerStyle;
@property (weak) id delegate;
@property (getter = isVertical) BOOL vertical;
@end
