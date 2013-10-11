//
//  FFGameButtonView.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFGameButtonView.h"
#import <QuartzCore/QuartzCore.h>

@interface FFGameButtonView ()

@property (nonatomic) UIButton *enter;
@property (nonatomic) UIButton *create;

@end

@implementation FFGameButtonView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        UIView *bg = [[UIView alloc] initWithFrame:CGRectMake(12, 10, 290, 37)];
        bg.backgroundColor = [FFStyle brightBlue];
        bg.layer.cornerRadius = 5;
        [self addSubview:bg];
        
        UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(145, 6, 1, 25)];
        separator.backgroundColor = [UIColor colorWithWhite:1 alpha:.2];
        [bg addSubview:separator];
        
        _create = [UIButton buttonWithType:UIButtonTypeCustom];
        _create.titleLabel.font = [FFStyle blockFont:18];
        [_create setTitle:NSLocalizedString(@"Create Game", nil) forState:UIControlStateNormal];
        _create.frame = CGRectMake(12, 0, frame.size.width/2-12, frame.size.height-5);
        [_create setTitleColor:[FFStyle white] forState:UIControlStateNormal];
        [_create setTitleColor:[FFStyle lightGrey] forState:UIControlStateHighlighted];
        [_create addTarget:self action:@selector(create:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_create];
        
        _enter = [UIButton buttonWithType:UIButtonTypeCustom];
        _enter.titleLabel.font = [FFStyle blockFont:18];
        [_enter setTitle:NSLocalizedString(@"My Games", nil) forState:UIControlStateNormal];
        _enter.frame = CGRectMake(frame.size.width/2, 0, frame.size.width/2-12, frame.size.height-5);
        [_enter setTitleColor:[FFStyle white] forState:UIControlStateNormal];
        [_enter setTitleColor:[FFStyle lightGrey] forState:UIControlStateHighlighted];
        [_enter addTarget:self action:@selector(enter:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_enter];
    }
    return self;
}

- (void)enter:(UIButton *)sender
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(gameButtonViewJoinGame)]) {
        [self.delegate gameButtonViewJoinGame];
    }
}

- (void)create:(UIButton *)sender
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(gameButtonViewCreateGame)]) {
        [self.delegate gameButtonViewCreateGame];
    }
}

@end
