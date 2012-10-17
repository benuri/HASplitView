//
//  HASplitView.m
//  Photographer
//
//  Created by Ben Uri on 7/6/12.
//  Copyright (c) 2012 Ben Uri. All rights reserved.
//

#import "HASplitView.h"
#include <vector>

@interface HASplitView ()
{
  NSMutableArray* _constraints;
  NSView* _uncollapsedView; // The view that is currently uncollapsing (there must only one at a time)
  BOOL _isRestoringUI;
  NSMapTable* _subviewsLengths;
}
@property NSArray *viewStackConstraints;
@property NSArray *heightConstraints;
@end
/*
 See this useful threads:
 http://www.cocoabuilder.com/archive/cocoa/318091-nssplitview-question-how-to-implement-my-own-adjustviews-style-method.html
 */
@implementation HASplitView

- (NSMapTable*)subviewLengths
{
  if (_subviewsLengths == nil)
  {
    @synchronized(self)
    {
      if (_subviewsLengths == nil)
      {
        _subviewsLengths = [NSMapTable mapTableWithKeyOptions:NSMapTableObjectPointerPersonality
                                                 valueOptions:NSMapTableObjectPointerPersonality];
      }
    }
  }
  return _subviewsLengths;
}

- (void)toggleSubviewShown:(NSView*)subview
{
  [subview setHidden: !subview.isHidden];
}
- (void)collapseSubview:(NSView*)subview
{
  if (subview.isHidden == YES) return;
  [subview setHidden: YES];
}
- (void)uncollapseSubview:(NSView*)subview
{
  if (subview.isHidden == NO) return;
  [subview setHidden: NO];
}

@synthesize viewStackConstraints=_viewStackConstraints, heightConstraints=_heightConstraints;

+ (BOOL)requiresConstraintBasedLayout
{
  return YES;
}

- (CGFloat)dividerThickness
{
  return 1;
}

- (BOOL)isFlipped
{
  return YES;
}

#pragma mark View Stack

// set up constraints to lay out subviews in a vertical stack with space between each consecutive pair.  This doesn't specify the heights of views, just that they're stacked up head to tail.
- (void)updateViewStackConstraints {
  if (!self.viewStackConstraints) {
    NSMutableArray *stackConstraints = [NSMutableArray array];
    NSDictionary *metrics = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:[self dividerThickness]], @"dividerThickness", nil];
    NSMutableDictionary *viewsDict = [NSMutableDictionary dictionary];
    
    // iterate over our subviews from top to bottom
    char orientation_char = self.isVertical ? 'H' : 'V';
    char ortho_orientation_char = self.isVertical ? 'V' : 'H';
    NSView *previousView = nil;
    for (NSView *currentView in [self subviews]) {

      if (currentView.isHidden)
        continue;
      
      [viewsDict setObject:currentView forKey:@"currentView"];
      
      if (!previousView) {
        // tie topmost view to the top of the container
        [stackConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:
                                               [NSString stringWithFormat:@"%c:|[currentView]",orientation_char]
                                                                                      options:0
                                                                                      metrics:metrics
                                                                                        views:viewsDict]];
      } else {
        // tie current view to the next one higher up
        [viewsDict setObject:previousView forKey:@"previousView"];
        [stackConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:
                                               [NSString stringWithFormat:@"%c:[previousView]-dividerThickness-[currentView]",orientation_char]
                                                                                      options:0
                                                                                      metrics:metrics
                                                                                        views:viewsDict]];
      }
      
      // each view should fill the splitview horizontally
      [stackConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:
                                             [NSString stringWithFormat:@"%c:|[currentView]|",ortho_orientation_char]
                                                                                    options:0
                                                                                    metrics:metrics 
                                                                                      views:viewsDict]];
      
      previousView = currentView;
    }
    
    // tie the bottom view to the bottom of the splitview
    if ([[self subviews] count] > 0) [stackConstraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:
                                                                            [NSString stringWithFormat:@"%c:[currentView]|",orientation_char]
                                                                                                                   options:0
                                                                                                                   metrics:metrics
                                                                                                                     views:viewsDict]];
    
    [self setViewStackConstraints:stackConstraints];
  }
}

- (NSArray *)viewStackConstraints
{
  return _viewStackConstraints;
}

// passing nil marks us as needing to update the stack constraints 
- (void)setViewStackConstraints:(NSArray *)stackConstraints {
  if (_viewStackConstraints != stackConstraints) {
    if (_viewStackConstraints)
      [self removeConstraints:_viewStackConstraints];
    _viewStackConstraints = stackConstraints;
    
    if (_viewStackConstraints)
    {
      [self addConstraints:_viewStackConstraints];
    }
    else
    {
      [self setNeedsUpdateConstraints:YES];
    }
  }
}

// need to recompute the view stack when we gain or lose a subview
- (void)didAddSubview:(NSView *)subview {
  [subview setTranslatesAutoresizingMaskIntoConstraints:NO];
  [subview addObserver:self forKeyPath:@"hidden" options:0 context:nil];
  [self setViewStackConstraints:nil];
  [super didAddSubview:subview];
}
- (void)willRemoveSubview:(NSView *)subview {
  [subview removeObserver:self forKeyPath:@"hidden"];
  [self setViewStackConstraints:nil];
  [self.subviewLengths removeObjectForKey:subview];
  [super willRemoveSubview:subview];
}

#pragma mark View Heights 

- (NSArray*)heightConstraints
{
  return _heightConstraints;
}
- (void)setHeightConstraints:(NSArray *)heightConstraints
{
  if (_heightConstraints != heightConstraints)
  {
    if (_heightConstraints)
      [self removeConstraints:_heightConstraints];
    
    _heightConstraints = heightConstraints;
    if (_heightConstraints)
    {
      [self addConstraints:_heightConstraints];
    }
    else
    {
      [self setNeedsUpdateConstraints:YES];
    }
  }
}

int DistanceOfViewWithIndexFromDividerWithIndex(int viewIndex, int dividerIndex) {
  return ABS(viewIndex - (dividerIndex + 0.5)) - 0.5;
}

/* make constraints specifying that each view wants its height to be the current percentage of the total space available
 
 The priorities are not all equal, though. The views closest to the dividerIndex maintain height with the lowest priority, and priority increases as we move away from the divider.
 
 Thus, the views closest to the divider are affected by divider dragging first.
 
 -1 for dividerIndex means that no divider is being dragged and all the height constraints should have the same priority.
 */
- (NSArray *)constraintsForHeightsWithPrioritiesLowestAroundDivider:(int)dividerIndex
{
  NSMutableArray *constraints = [NSMutableArray array];
 
  NSLayoutAttribute lengthAttribute = self.isVertical ? NSLayoutAttributeWidth : NSLayoutAttributeHeight;
  
  if (dividerIndex != -2)
  {
    // Fix the current length while dragging a divider
    CGFloat currentLength = self.isVertical ? NSWidth(self.frame) : NSHeight(self.frame);
    NSLayoutConstraint* totalLengthConstraint = [NSLayoutConstraint constraintWithItem:self attribute:lengthAttribute relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:currentLength];
    [constraints addObject: totalLengthConstraint];
  }
  
  CGFloat uncollapsedViewLength = 0;
  if (_uncollapsedView)
  {
    uncollapsedViewLength = [[self.subviewLengths objectForKey:_uncollapsedView] doubleValue];
  }

  CGFloat totalVisibleViewsLength = 0;
  NSMutableArray* visibleSubviews = [NSMutableArray array];
  NSInteger numberOfVisibleViews = 0;
  {
    // Count visible views
    for (NSView* v in [self subviews])
    {
      if (v.isHidden) continue;
      numberOfVisibleViews++;
      [visibleSubviews addObject:v];
    }
  }
  
  CGFloat spaceForAllDividers = [self dividerThickness] * (numberOfVisibleViews - 1);
// CGFloat boundsLength = self.isVertical ? NSWidth([self bounds]) : NSHeight([self bounds]);
  
  
//  CGFloat spaceForAllViews = boundsLength - spaceForAllDividers;
  CGFloat priorityIncrement = 1.0 / numberOfVisibleViews;
  
  for (NSView* v in visibleSubviews)
  {
    CGFloat length = [[self.subviewLengths objectForKey:v] doubleValue];
    if (length < 1)
    {
      NSSize fittingSize = [v fittingSize];
      length = self.isVertical ? fittingSize.width : fittingSize.height;
      [self.subviewLengths setObject:[NSNumber numberWithDouble:length] forKey:v];
    }
    // length = length >= 1 ? length : spaceForAllViews / numberOfVisibleViews;
    
    if (v == _uncollapsedView)
      uncollapsedViewLength = length;
    else
      totalVisibleViewsLength += length;
  }
  
  // uncollapsedViewLength = MIN(uncollapsedViewLength, spaceForAllViews / numberOfVisibleViews);
  
  std::vector<CGFloat> percentsOfTotalLength([visibleSubviews count]);
  CGFloat totalPercents = 0;
  for (NSUInteger i = 0; i < [visibleSubviews count]; i++)
  {
    NSView *v = [visibleSubviews objectAtIndex:i];
    
    CGFloat length = [[self.subviewLengths objectForKey:v] doubleValue];
    
    if (v != _uncollapsedView && _uncollapsedView)
    {
      CGFloat spaceForUncollapsedViewLengthAndItsDivider = uncollapsedViewLength + (uncollapsedViewLength > 0 ? [self dividerThickness] : 0);
      length -= spaceForUncollapsedViewLengthAndItsDivider / (numberOfVisibleViews-1);
    }
    
    CGFloat percentOfTotalLength = length / totalVisibleViewsLength;
    // NSLog(@"percentOfTotalLength=%f", percentOfTotalLength);
    totalPercents += percentOfTotalLength;
    percentsOfTotalLength[i] = percentOfTotalLength;
  }
  // NSLog(@"totalPercents=%f", totalPercents);
  if (totalPercents > 0)
  {
    for (NSUInteger i = 0; i < percentsOfTotalLength.size(); i++)
    {
      NSView *v = [visibleSubviews objectAtIndex:i];
      CGFloat percentOfTotalLength = percentsOfTotalLength[i] / totalPercents;
      // Constrain: v.height == (self.height - spaceForAllDividers) * percentOfTotalHeight
      NSLayoutConstraint *lengthConstraint = [NSLayoutConstraint constraintWithItem:v
                                                                          attribute:lengthAttribute
                                                                          relatedBy:NSLayoutRelationEqual
                                                                             toItem:self
                                                                          attribute:lengthAttribute
                                                                         multiplier:percentOfTotalLength
                                                                           constant:-spaceForAllDividers * percentOfTotalLength];
      
      if (dividerIndex == -2) {
        [lengthConstraint setPriority:NSLayoutPriorityDefaultLow];
      } else {
        [lengthConstraint setPriority:NSLayoutPriorityDefaultLow + priorityIncrement*DistanceOfViewWithIndexFromDividerWithIndex(i, dividerIndex)];
      }
      
      [constraints addObject:lengthConstraint];
    }
  }
  _uncollapsedView = nil;
  return constraints;
}

- (void)updateHeightConstraints {
  if (!self.heightConstraints) self.heightConstraints = [self constraintsForHeightsWithPrioritiesLowestAroundDivider:-2];
}

#pragma mark Update Layout Constraints Override 

- (void)updateConstraints {
  [super updateConstraints];
  [self updateViewStackConstraints];
  [self updateHeightConstraints];
}

#pragma mark Divider Dragging 

- (void)layout
{
  [super layout];
  [self.window invalidateCursorRectsForView:self];
  
  // Save visible subview lengths. We need this because hidden subviews may have
  // a zero frame after layout.
  // NSView* previousView = nil;
  // NSLog(@"splitview.frame=%@", NSStringFromRect(self.frame));
  if (MAX(NSHeight(self.frame), NSWidth(self.frame)) > 5000)
  {
    NSAssert(false, @"Internal Error in Auto Layout");
  }
  
  for (NSView* v in self.subviews)
  {
    if (!v.isHidden)
    {
      NSRect frame = v.frame;
      CGFloat length = self.isVertical ? frame.size.width : frame.size.height;
      [self.subviewLengths setObject:[NSNumber numberWithDouble:length] forKey:v];
      // NSLog(@"\tv.frame=%@", NSStringFromRect(v.frame));
    }
  }
}

- (int)dividerIndexForPoint:(NSPoint)point
{
  __block int dividerIndex = -1;

  if (self.subviews.count == 0)
    return dividerIndex;
  
  CGFloat cursorRectThickness = MIN([self dividerThickness], 5);
  CGFloat cursorRectOffset = MAX(0, (cursorRectThickness - [self dividerThickness])/2);
  
  NSRect dividerRect = NSMakeRect(0, 0,
                                  self.isVertical ? cursorRectThickness : NSWidth(self.bounds),
                                  self.isVertical ? NSHeight(self.bounds) : cursorRectThickness);

  NSView* previousView = nil;
  int i = 0;
  for (NSView* v in self.subviews)
  {
    if (v.isHidden)
      continue;
    // NSLog(@"v.frame=%@", NSStringFromRect(v.frame));
    if (previousView != nil)
    {
      if (self.isVertical)
        dividerRect.origin.x = NSMaxX(previousView.frame) - cursorRectOffset;
      else
      {
        dividerRect.origin.y = self.isFlipped ? NSMaxY(previousView.frame) : NSMaxY(v.frame);
        dividerRect.origin.y -= cursorRectOffset;
      }
      // NSLog(@"dividerRect=%@", NSStringFromRect(dividerRect));
      if (NSPointInRect(point, dividerRect))
      {
        dividerIndex = i - 1;
        break;
      }
    }
    i++;
    previousView = v;
  }
  return dividerIndex;
}

-(void)resetCursorRects
{
  // NSLog(@"%s", __func__);
  NSCursor * cursor = self.isVertical ? [NSCursor resizeLeftRightCursor] : [NSCursor resizeUpDownCursor];

  if (!_draggingConstraint)
  {
    CGFloat cursorRectThickness = MIN([self dividerThickness], 5);
    CGFloat cursorRectOffset = MAX(0, (cursorRectThickness - [self dividerThickness])/2);
    
    NSRect dividerRect = NSMakeRect(0, 0,
                                    self.isVertical ? cursorRectThickness : NSWidth(self.bounds),
                                    self.isVertical ? NSHeight(self.bounds) : cursorRectThickness);

    NSView* previousView = nil;
    for (NSView* v in self.subviews)
    {
      if (v.isHidden)
        continue;
      // NSLog(@"v.frame=%@", NSStringFromRect(v.frame));
      if (previousView != nil)
      {
        if (self.isVertical)
          dividerRect.origin.x = NSMaxX(previousView.frame) - cursorRectOffset;
        else
        {
          dividerRect.origin.y = self.isFlipped ? NSMaxY(previousView.frame) : NSMaxY(v.frame);
          dividerRect.origin.y -= cursorRectOffset;
        }
        
        [self addCursorRect:dividerRect
                     cursor:cursor];
      }
      previousView = v;
    }
  }
}

- (BOOL)mouseDownCanMoveWindow
{
  return NO;
}

-(void)mouseDown:(NSEvent *)theEvent
{
  NSPoint locationInSelf = [self convertPoint:[theEvent locationInWindow] fromView:nil];
  int dividerIndex = [self dividerIndexForPoint:locationInSelf];
  // NSLog(@"locationInSelf = %@", NSStringFromPoint(locationInSelf));
  if (dividerIndex != -1)
  {
    // First we lock the heights in place for the given dividerIndex
    self.heightConstraints = [self constraintsForHeightsWithPrioritiesLowestAroundDivider:dividerIndex];
    
    // Now we add a constraint that forces the bottom edge of the view above the divider to align with the mouse location
    NSView *viewAboveDivider = [[self subviews] objectAtIndex:dividerIndex];
    char orientation_char = self.isVertical ? 'H' : 'V';
    _draggingConstraint = [[NSLayoutConstraint constraintsWithVisualFormat:[NSString stringWithFormat:
                                                                            @"%c:[viewAboveDivider]-100-|", orientation_char]
                                                                    options:0
                                                                    metrics:nil
                                                                      views:NSDictionaryOfVariableBindings(viewAboveDivider)] lastObject];
    [_draggingConstraint setPriority:NSLayoutPriorityDragThatCannotResizeWindow];
    _draggingConstraint.constant = self.isVertical ? (NSWidth([self bounds]) - NSMaxX(viewAboveDivider.frame)) : (self.isFlipped ? (NSHeight([self bounds]) - NSMaxY(viewAboveDivider.frame)) : NSMinY(viewAboveDivider.frame));
    _draggingConstraintConstantAtMouseDown = _draggingConstraint.constant;
    
    [self addConstraint:_draggingConstraint];
    
    // NSLog(@"_draggingConstraint=%@", _draggingConstraint);
    
    _mouseDownLocation = locationInSelf;
    
    [[self window] disableCursorRects];
    
    NSCursor * cursor = self.isVertical ? [NSCursor resizeLeftRightCursor] : [NSCursor resizeUpDownCursor];
    [cursor push];
    
    for (NSView* v in self.subviews)
    {
      [v viewWillStartLiveResize];
    }
  }
  else
  {
    [super mouseDown:theEvent];
  }
}

- (void)mouseDragged:(NSEvent *)theEvent
{
  if (_draggingConstraint)
  {
    // update the dragging constraint for the new location
    NSPoint locationInSelf = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    NSPoint delta = NSMakePoint(_mouseDownLocation.x - locationInSelf.x, _mouseDownLocation.y - locationInSelf.y);
    
    [_draggingConstraint setConstant:self.isVertical ? _draggingConstraintConstantAtMouseDown + delta.x :
     (_draggingConstraintConstantAtMouseDown + delta.y)];
    // NSLog(@"_draggingConstraint=%@", _draggingConstraint);
    [self setNeedsDisplay: YES];
  }
  else
  {
    [super mouseDragged:theEvent];
  }
}

- (void)mouseUp:(NSEvent *)theEvent
{
  if (_draggingConstraint) {
    [self removeConstraint:_draggingConstraint];
    _draggingConstraint = nil;
    
    // We lock the current heights in place
    self.heightConstraints = [self constraintsForHeightsWithPrioritiesLowestAroundDivider:-2];
    [self setNeedsDisplay: YES];
    
    [[NSCursor currentCursor] pop];
    
    for (NSView* v in self.subviews)
    {
      [v viewDidEndLiveResize];
    }
    [[self window] enableCursorRects];
    [[self window] resetCursorRects];
    [self invalidateRestorableState];
  }
  else
  {
    [super mouseUp:theEvent];
  }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  if ([keyPath isEqualToString:@"hidden"])
  {
    if ([self.subviews containsObject:object])
    {
      NSView* v = (NSView*)object;
      if (!v.isHidden && !_isRestoringUI)
      {
#if DEBUG
        if (_uncollapsedView != nil)
          NSLog(@"Internal error here %s.", __func__);
#endif
        _uncollapsedView = v;
      }
      [self setHeightConstraints:nil];
      [self setViewStackConstraints:nil];
      [self setNeedsDisplay: YES];
      [self invalidateRestorableState];
      return;
    }
    else
    {
      [object removeObserver:self];
    }
  }
  [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark Drawing 
- (void)disableUpdatedUntilFlush
{
  [self.window disableScreenUpdatesUntilFlush];
}
- (void)drawRect:(NSRect)dirtyRect
{
  [[NSColor redColor] set];
  NSRectFill(dirtyRect);
}

- (void)adjustSubviews
{
  [self disableUpdatedUntilFlush];
  [self setNeedsUpdateConstraints:YES];
}

- (void)adjustSubviewsWithConstraints
{
  [self adjustSubviews];
}

#pragma mark -
#pragma mark State Restoration

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
  [super encodeRestorableStateWithCoder:coder];
  
  NSMutableArray* lengths = [NSMutableArray arrayWithCapacity:self.subviews.count];
  NSMutableArray* hiddens = [NSMutableArray arrayWithCapacity:self.subviews.count];
  NSMutableArray* subviewsStates = [NSMutableArray arrayWithCapacity:self.subviews.count];
  
  NSUInteger idx = 0;
  for (NSView* v in self.subviews)
  {
    CGFloat length = [[self.subviewLengths objectForKey:v] doubleValue];
    [lengths setObject: [NSNumber numberWithDouble:length] atIndexedSubscript:idx];
    [hiddens setObject: [NSNumber numberWithBool:v.isHidden] atIndexedSubscript:idx];
    // Recursively encode subviews' states:
    {
      NSMutableData* subviewState = [NSMutableData data];
      NSKeyedArchiver* archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:subviewState];
      [v encodeRestorableStateWithCoder:archiver];
      [archiver finishEncoding];
      [subviewsStates setObject:subviewState atIndexedSubscript:idx];
    }
    idx++;
  }
  
  [coder encodeObject:lengths forKey:@"lengths"];
  [coder encodeObject:hiddens forKey:@"hiddens"];
  [coder encodeObject:subviewsStates forKey:@"subviewsStates"];
}

- (void)restoreStateWithCoder:(NSCoder *)coder
{
  NSLog(@"%s", __func__);
  [super restoreStateWithCoder:coder];
  
  NSArray* lengths = [coder decodeObjectForKey:@"lengths"];
  NSArray* hiddens = [coder decodeObjectForKey:@"hiddens"];
  NSArray* subviewsStates = [coder decodeObjectForKey:@"subviewsStates"];
  
  if ([lengths count] != [hiddens count] ||
      [lengths count] != [subviewsStates count] ||
      [lengths count] != [self.subviews count])
  {
    return;
  }
  
  _isRestoringUI = YES;
  NSUInteger idx = 0;
  for (NSView* v in self.subviews)
  {
    CGFloat length = [[lengths objectAtIndex:idx] doubleValue];
    CGFloat h = [[hiddens objectAtIndex:idx] doubleValue];
    
    [self.subviewLengths setObject:[NSNumber numberWithDouble:length] forKey:v];
    [v setHidden:h];
    
    // Recursively decode subviews' states:
    {
      NSData* subviewState = [subviewsStates objectAtIndex:idx];
      NSKeyedUnarchiver* unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:subviewState];
      [v restoreStateWithCoder:unarchiver];
    }
    
    idx++;
  }
  [self setHeightConstraints:nil];
  [self setViewStackConstraints:nil];
  [self setNeedsDisplay: YES];
  _isRestoringUI = NO;
}

@end
