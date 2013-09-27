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
        
        _price = [[UILabel alloc] initWithFrame:CGRectMake(82, 50, 140, 16)];
        _price.backgroundColor = [UIColor clearColor];
        _price.font = [FFStyle mediumFont:14];
        _price.textColor = [FFStyle darkGreyTextColor];
        [self.contentView addSubview:_price];
        
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
    } else {
        _emptyPosition.hidden = YES;
        _select.hidden = YES;
        _name.hidden = NO;
        _team.hidden = NO;
        _price.hidden = NO;
        _trade.hidden = NO;
        _name.text = player[@"name"];
        NSString *ppg = [player[@"ppg"] isEqual:[NSNull null]] ? @"0" : player[@"ppg"];
        _team.text = [NSString stringWithFormat:@"%@ Team: %@ PPG: %@", player[@"position"], player[@"team"], ppg];
        _price.text = [NSString stringWithFormat:@"$%@", player[@"buy_price"]];
        if ([player[@"image"] isKindOfClass:[NSString class]]) {
            [_img setImageWithURL:[NSURL URLWithString:player[@"image"]]
                 placeholderImage:[UIImage imageNamed:@"rosterslotempty.png"]];
        } else {
            _img.image = [UIImage imageNamed:@"rosterslotempty.png"];
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

@end
