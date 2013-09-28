//
//  FFRosterSlotCell.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/26/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFRosterSlotCell.h"
#import <AFNetworking/UIImageView+AFNetworking.h>


@interface FFRosterSlotCell ()

@property (nonatomic) UIImageView *img;
@property (nonatomic) UILabel *emptyPosition;
@property (nonatomic) UILabel *name;
@property (nonatomic) UILabel *team;
@property (nonatomic) UILabel *price;
@property (nonatomic) UIButton *select;
@property (nonatomic) UIButton *trade;
@property (nonatomic) UIButton *stats;
@property (nonatomic) UILabel *diff;

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
        
        UIImageView *mask = [[UIImageView alloc] initWithFrame:CGRectMake(15, 11, 57, 57)];
        mask.backgroundColor = [UIColor clearColor];
        mask.image = [UIImage imageNamed:@"playerselectmask.png"];
        [self addSubview:mask];
        
        _team = [[UILabel alloc] initWithFrame:CGRectMake(82, 32, 140, 16)];
        _team.backgroundColor = [UIColor clearColor];
        _team.font = [FFStyle regularFont:13];
        _team.textColor = [FFStyle greyTextColor];
        [self.contentView addSubview:_team];
        
        _name = [[UILabel alloc] initWithFrame:CGRectMake(82, 13, 140, 16)];
        _name.backgroundColor = [UIColor clearColor];
        _name.font = [FFStyle regularFont:17];
        _name.textColor = [FFStyle darkGreyTextColor];
        [self.contentView addSubview:_name];
        
        _price = [[UILabel alloc] initWithFrame:CGRectMake(82, 50, 80, 16)];
        _price.backgroundColor = [UIColor clearColor];
        _price.font = [FFStyle mediumFont:14];
        _price.textColor = [FFStyle darkGreyTextColor];
        [self.contentView addSubview:_price];
        
        _diff = [[UILabel alloc] initWithFrame:CGRectMake(162, 50, 80, 16)];
        _diff.backgroundColor = [UIColor clearColor];
        _diff.font = [FFStyle regularFont:14];
        _diff.textColor = [FFStyle brightGreen];
        [self.contentView addSubview:_diff];
        
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
        
        _trade = [FFStyle coloredButtonWithText:NSLocalizedString(@"Trade", nil)
                                           color:[FFStyle brightRed]
                                     borderColor:[FFStyle white]];
        _trade.frame = CGRectMake(224, 21, 80, 38);
        _trade.hidden = YES;
        [_trade addTarget:self action:@selector(replace:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_trade];
        
        _stats = [FFStyle coloredButtonWithText:NSLocalizedString(@"Stats", nil)
                                          color:[FFStyle brightBlue]
                                    borderColor:[FFStyle white]];
        _stats.frame = CGRectMake(224, 21, 80, 38);
        _stats.hidden = YES;
        [_stats addTarget:self action:@selector(stats:) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_stats];
        
        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(7, 78, 306, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:.5];
        [self.contentView addSubview:sep];
        
        sep = [[UIView alloc] initWithFrame:CGRectMake(7, 79, 306, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:1 alpha:.5];
        [self.contentView addSubview:sep];
    }
    return self;
}

- (BOOL)isInPlay
{
    return (![self.market.state isEqualToString:@"published"] && ![self.roster.state isEqualToString:@"in_progress"]);
}

- (BOOL)marketStarted
{
    return [self.market.startedAt compare:[NSDate date]] == NSOrderedAscending;
}

- (void)setPlayer:(id)player
{
    _player = player;
    
    if ([player isKindOfClass:[NSString class]]) {
        // it's an empty slot
        _emptyPosition.text = player;
        _emptyPosition.hidden = NO;
        _select.hidden = NO;
        _name.hidden = YES;
        _team.hidden = YES;
        _price.hidden = YES;
        _trade.hidden = YES;
        _diff.hidden = YES;
        _stats.hidden = YES;
    } else {
        _emptyPosition.hidden = YES;
        _select.hidden = YES;
        _name.hidden = NO;
        _team.hidden = NO;
        _price.hidden = NO;
        
        _name.text = player[@"name"];
        NSString *ppg = [player[@"ppg"] isEqual:[NSNull null]] ? @"0" : player[@"ppg"];
        _team.text = [NSString stringWithFormat:@"%@ %@ %@ PPG", player[@"position"], player[@"team"], ppg];
        
        if ([player[@"image"] isKindOfClass:[NSString class]]) {
            [_img setImageWithURL:[NSURL URLWithString:player[@"image"]]
                 placeholderImage:[UIImage imageNamed:@"rosterslotempty.png"]];
        } else {
            _img.image = [UIImage imageNamed:@"rosterslotempty.png"];
        }
        if ([self isInPlay]) {
            _price.text = [NSString stringWithFormat:@"$%@", player[@"purchase_price"]];
            _price.frame = CGRectMake(82, 50, [_price.text sizeWithFont:_price.font].width, 16);
            _diff.hidden = NO;
            double diff =  (([player[@"sell_price"] doubleValue] - [player[@"purchase_price"] doubleValue])
                            / [player[@"purchase_price"] doubleValue]) * 100;
            _diff.text = [NSString stringWithFormat:@"%.2lf%%", diff];
            _diff.frame = CGRectMake(CGRectGetMaxX(_price.frame)+5, 50, 80, 16);
        } else {
            _diff.hidden = YES;
            _price.text = [NSString stringWithFormat:@"$%@", player[@"buy_price"]];
            _price.frame = CGRectMake(82, 50, 80, 16);
        }
        if (![self marketStarted]) {
            _trade.hidden = NO;
            _stats.hidden = YES;
        } else {
            _trade.hidden = YES;
            _stats.hidden = NO;
            [_stats setTitle:[NSString stringWithFormat:@"%@ %@", player[@"score"], NSLocalizedString(@"Points", nil)]
                    forState:UIControlStateNormal];
        }
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

- (void)stats:(UIButton *)sender
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(rosterCellStatsForPlayer::)]) {
        [self.delegate rosterCellStatsForPlayer:self];
    }
}

@end
