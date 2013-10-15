//
//  FFBubblePicker.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/28/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFBubblePicker.h"
#import <QuartzCore/QuartzCore.h>


@interface FFBubblePicker ()
{
    NSMutableArray *_items;
    NSMutableArray *_buttons; // one for every item
    CGFloat _intrinsicHeight;
    UITapGestureRecognizer *_tapRecognizer;
    UITextField *_textField;
}

- (void)layoutBubbleViews:(BOOL)animated;
- (CGFloat)widthForButton:(UIButton *)b;

@end


#define BUTTON_FONT [FFStyle regularFont:16]
#define kButtonLeftPadding 5.0f
#define kButtonRightPadding 5.0f
#define kButtonTopPadding 5.0f
#define kButtonBottomPadding 5.0f
#define kButtonContainerWidth 260.0f
#define kButtonContainerPaddingTop 0.0f
#define kButtonContainerPaddingBottom 0.0f
#define kButtonHeight 25.0f


@implementation FFBubblePicker

- (id)init
{
    self = [super init];
    if (self) {
        _buttons = [NSMutableArray array];
        _items = [NSMutableArray array];
        _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTap:)];
        [self addGestureRecognizer:_tapRecognizer];
        _textField = [[FFBubblePicker_TextField alloc] initWithFrame:CGRectMake(0, 0, 100, kButtonHeight)];
        _textField.autocorrectionType = UITextAutocorrectionTypeNo;
        _textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _textField.font = [FFStyle regularFont:_textField.font.pointSize];
        _textField.textColor = [FFStyle black];
        _textField.delegate = self;
        _textField.backgroundColor = [UIColor clearColor];
        [_textField addTarget:self action:@selector(textFieldChanged:) forControlEvents:UIControlEventEditingChanged];
        [self addSubview:_textField];
    }
    return self;
}

- (void)clear
{
    for (int i = 0; i < _buttons.count; i++) {
        UIButton *b = [_buttons objectAtIndex:i];
        [b removeFromSuperview];
    }
    [_buttons removeAllObjects];
    [_items removeAllObjects];
    if (self.delegate && [self.delegate respondsToSelector:@selector(bubblePickerDidUpdateItems:)]) {
        [self.delegate bubblePickerDidUpdateItems:self];
    }
    [self layoutBubbleViews:NO];
}

- (IBAction)didTap:(UITapGestureRecognizer *)sender
{
    NSLog(@"did tap on your face butt");
    [_textField becomeFirstResponder];
}

- (NSArray *)items
{
    return [_items copy];
}

- (NSString *)textViewValue
{
    return _textField.text;
}

- (void)setTextViewValue:(NSString *)value
{
    _textField.text = value;
}

- (void)addItem:(id)item title:(NSString *)title animated:(BOOL)animated
{
    if ([_items containsObject:item]) {
        return;
    }
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.layer.backgroundColor = [FFStyle brightBlue].CGColor;
    b.layer.cornerRadius = 2;
    [b setTitle:title forState:UIControlStateNormal];
    [b setShowsTouchWhenHighlighted:NO];
    [b setTitleColor:[FFStyle white] forState:UIControlStateNormal];
//    [b setTitleShadowColor:[UIColor colorWithWhite:0 alpha:.25] forState:UIControlStateNormal];
//    [b.titleLabel setShadowOffset:CGSizeMake(0, -.5)];
    [b setTitleEdgeInsets:UIEdgeInsetsMake(2, 0, 0, 0)];
    [b.titleLabel setFont:BUTTON_FONT];
    CGFloat width;
    if (_buttons.count) {
        width = [self widthForButton:_buttons[0]];
    } else {
        width = [[b currentTitle] sizeWithFont:BUTTON_FONT].width + 20.0f;
    }
    b.frame = CGRectMake(0, 0, width, kButtonHeight);
    [_buttons addObject:b];
    [_items addObject:item];
    if (self.delegate && [self.delegate respondsToSelector:@selector(bubblePickerDidUpdateItems:)]) {
        [self.delegate bubblePickerDidUpdateItems:self];
    }
    [b addTarget:self action:@selector(didTouchButton:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    [self layoutBubbleViews:animated];
}

- (void)didTouchButton:(UIButton *)sender
{
    int i = [_buttons indexOfObject:sender];
    if (self.delegate && [self.delegate respondsToSelector:@selector(bubblePicker:didSelectItem:)]) {
        [self.delegate bubblePicker:self didSelectItem:_items[i]];
    }
}

- (id)removeItem:(id)item animated:(BOOL)animated
{
    int i = [_items indexOfObject:item];
    [_items removeObjectAtIndex:i];
    if (self.delegate && [self.delegate respondsToSelector:@selector(bubblePickerDidUpdateItems:)]) {
        [self.delegate bubblePickerDidUpdateItems:self];
    }
    UIButton *b = _buttons[i];
    [_buttons removeObjectAtIndex:i];
    [b removeFromSuperview];
    [self layoutBubbleViews:YES];
    return item;
}

- (CGFloat)widthForButton:(UIButton *)b
{
    return [[b currentTitle] sizeWithFont:BUTTON_FONT].width + 15.0f;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self layoutBubbleViews:NO];
}

- (CGSize)intrinsicContentSize
{
    return CGSizeMake(UIViewNoIntrinsicMetric, MAX(_intrinsicHeight, 28));
}

- (CGRect)_textViewFrameForRow:(NSUInteger)row rowWidth:(CGFloat)rowWidth
{
    CGFloat top = (row * (kButtonHeight + kButtonTopPadding)) + kButtonContainerPaddingTop;
    CGFloat left = rowWidth + kButtonRightPadding;
    if (!_textField.text.length && !_textField.isFirstResponder) {
        return CGRectMake(left, top, 6, kButtonHeight + 4);
    }
    CGFloat width = [_textField.text sizeWithFont:_textField.font].width;
    
    if ((width + left + kButtonRightPadding) > CGRectGetMaxX(self.bounds)) {
        // text field should go on new row
        left = kButtonLeftPadding;
        top = ((row + 1) * (kButtonHeight + kButtonTopPadding)) + kButtonContainerPaddingTop;
    }
    return CGRectMake(left, top, MIN(width + 6, self.bounds.size.width), kButtonHeight + 4);
}

- (void)layoutBubbleViews:(BOOL)animated
{
    NSUInteger row = 0;
    NSUInteger i = 0;
    CGFloat rowWidth = 0;
    CGFloat buttonWidth = 0.0f;
    CGRect *changes = (CGRect *)malloc(sizeof(CGRect) * _buttons.count);
    
    for (UIButton *b in _buttons) {
        buttonWidth = [self widthForButton:b];
        CGFloat newRowWidth = rowWidth + buttonWidth + kButtonLeftPadding + kButtonRightPadding;
        if (newRowWidth > CGRectGetMaxX(self.bounds)) {
            row += 1;
            rowWidth = 0;
            newRowWidth = kButtonLeftPadding + kButtonRightPadding + buttonWidth;
        } else {
            newRowWidth -= kButtonRightPadding;
        }
        changes[i] = CGRectMake(rowWidth + kButtonLeftPadding,  // x
                                (row * (kButtonHeight + kButtonTopPadding)) + kButtonContainerPaddingTop, // y
                                buttonWidth, // width
                                kButtonHeight); // height
        rowWidth = newRowWidth;
        i++;
    }
    
    CGRect textViewFrame = [self _textViewFrameForRow:row rowWidth:rowWidth];
    textViewFrame.size.height -= 4;
    // use the bottom of the bottom-most button if there is no text, otherwise just use the bottom of the text view
    if (_buttons.count || _textField.isFirstResponder) {
        _intrinsicHeight = (CGRectGetMaxY(_textField.text.length || _textField.isFirstResponder
                                          ? textViewFrame
                                          : changes[i - 1]) + kButtonContainerPaddingBottom);
    } else {
        _intrinsicHeight = 25;
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(bubblePicker:willUpdateHeight:)]) {
        [self.delegate bubblePicker:self willUpdateHeight:_intrinsicHeight];
    }
    
    if (animated) {
        [UIView beginAnimations:nil context:nil];
        [UIView setAnimationDuration:.2f];
        [self invalidateIntrinsicContentSize];
        for (int j = 0; j < _buttons.count; j++) {
            [_buttons[j] setFrame:changes[j]];
        }
        _textField.frame = textViewFrame;
        [UIView commitAnimations];
    } else {
        [self invalidateIntrinsicContentSize];
        for (int j = 0; j < _buttons.count; j++) {
            [_buttons[j] setFrame:changes[j]];
        }
        _textField.frame = textViewFrame;
    }
    free(changes);
}

- (void)resetTextView
{
    _textField.text = @"";
    [self textFieldChanged:_textField];
}

- (void)openAutocomplete
{
    [_textField becomeFirstResponder];
}

- (void)closeAutocomplete
{
    [_textField resignFirstResponder];
}

- (IBAction)textFieldChanged:(UITextField *)sender
{
    NSLog(@"text field changed to %@", sender.text);
    [self setNeedsLayout];
    if (self.delegate && [self.delegate respondsToSelector:@selector(bubblePicker:didUpdateText:)]) {
        [self.delegate bubblePicker:self didUpdateText:sender.text];
    }
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(bubblePickerWillBeginEditing:)]) {
        [self.delegate bubblePickerWillBeginEditing:self];
    }
    [self setNeedsLayout];
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
    NSLog(@"text field will end");
    [self setNeedsLayout];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    textField.text = @"";
    if (self.delegate && [self.delegate respondsToSelector:@selector(bubblePickerDidEndEditing:)]) {
        [self.delegate bubblePickerDidEndEditing:self];
    }
}

@end


// custom UITextField implementation that works with Myriad Pro
@implementation FFBubblePicker_TextField

#define INSET_X 0
#define INSET_Y 4
#define INSET_Y_COMPENSATION 0
#define INSET_Y_COMPENSATION_EDITING 2

- (CGRect)textRectForBounds:(CGRect)bounds
{
    int compensation = INSET_Y_COMPENSATION;
    if (self.editing) {
        compensation = INSET_Y_COMPENSATION_EDITING;
    }
    return CGRectMake(INSET_X, INSET_Y - compensation, bounds.size.width - INSET_X, bounds.size.height - INSET_Y);
}

- (CGRect)placeholderRectForBounds:(CGRect)bounds
{
    return CGRectMake(INSET_X, INSET_Y, bounds.size.width - INSET_X, bounds.size.height - INSET_Y);
}

- (CGRect)editingRectForBounds:(CGRect)bounds
{
    int compensation = INSET_Y_COMPENSATION;
    if (self.editing) {
        compensation = INSET_Y_COMPENSATION_EDITING;
    }
    return CGRectMake(INSET_X, INSET_Y - compensation, bounds.size.width - INSET_X, bounds.size.height - INSET_Y);
}

@end

