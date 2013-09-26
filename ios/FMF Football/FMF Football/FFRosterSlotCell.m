//
//  FFRosterSlotCell.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/26/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFRosterSlotCell.h"


@interface FFRosterSlotCell ()

@property (nonatomic) UIImageView *img;
@property (nonatomic) UILabel *emptyPosition;
@property (nonatomic) UIButton *select;
@property (nonatomic) UIButton *trade;

@end


@implementation FFRosterSlotCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.contentView.backgroundColor = [UIColor colorWithWhite:.94 alpha:1];
        _img = [[UIImageView alloc] initWithFrame:CGRectMake(15, 11, 57, 57)];
        _img.backgroundColor = [UIColor clearColor];
        _img.image = [UIImage imageNamed:@"rosterslotempty.png"];
        [self.contentView addSubview:_img];
        
        _emptyPosition = [[UILabel alloc] initWithFrame:CGRectMake(82, 0, 80, self.frame.size.height)];
        _emptyPosition.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        _emptyPosition.backgroundColor = [UIColor clearColor];
        _emptyPosition.font = [FFStyle regularFont:19];
        _emptyPosition.textColor = [FFStyle greyTextColor];
        [self.contentView addSubview:_emptyPosition];
        
        _select = [FFStyle coloredButtonWithText:NSLocalizedString(@"Select", nil)
                                           color:[FFStyle brightGreen]
                                     borderColor:[FFStyle white]];
        _select.frame = CGRectMake(224, 21, 80, 38);
        [_select addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_select];
        
        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(7, 78, 306, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:.5];
        [self.contentView addSubview:sep];
        
        sep = [[UIView alloc] initWithFrame:CGRectMake(7, 79, 306, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:1 alpha:.5];
        [self.contentView addSubview:sep];
    }
    return self;
}

- (void)setPlayer:(id)player
{
    if ([player isKindOfClass:[NSString class]]) {
        // it's an empty slot
        _emptyPosition.text = player;
    }
}

- (void)select:(UIButton *)sender
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(rosterCellSelectPlayer:)]) {
        [self.delegate rosterCellSelectPlayer:self];
    }
}

- (void)replace:(UIButton *)sender
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(rosterCellReplacePlayer:)]) {
        [self.delegate rosterCellReplacePlayer:self];
    }
}

@end
