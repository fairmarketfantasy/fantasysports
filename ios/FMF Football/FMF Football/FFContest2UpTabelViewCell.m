//
//  FFMarket2UpTabelViewCell.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFContest2UpTabelViewCell.h"
#import <AFNetworking/UIImageView+AFNetworking.h>


@interface FFContestBitView : UIView

@property (nonatomic) FFContest *contest;

@property (nonatomic) UIImageView *img;
@property (nonatomic) UILabel *label;

@end

@implementation FFContestBitView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _img = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 35, 35)];
        _img.backgroundColor = [UIColor clearColor];
        _img.contentMode = UIViewContentModeScaleAspectFit;
        _img.center = CGPointMake(80, 45);
        _img.alpha = .5;
        [self addSubview:_img];
        
        UIImageView *_circle = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"contestcircle.png"]];
        _circle.frame = CGRectMake(0, 0, 69, 69);
        _circle.center = CGPointMake(80, 45);
        [self addSubview:_circle];
        
        _label = [[UILabel alloc] initWithFrame:CGRectMake(15, 85, 130, 50)];
        _label.numberOfLines = 3;
        _label.font = [FFStyle regularFont:14];

        _label.backgroundColor = [UIColor clearColor];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.textColor = [FFStyle greyTextColor];
//        _label.adjustsFontSizeToFitWidth = YES;
//        _label.adjustsLetterSpacingToFitWidth = YES;
        [self addSubview:_label];
    }
    return self;
}

- (void)setContest:(FFContest *)contest
{
    _contest = contest;
    
    
    NSString *iconUrl = [NSString stringWithFormat:@"%@%@",
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:SBApiBaseURLKey],
                         contest.iconUrl];
    [_img setImageWithURL:[NSURL URLWithString:iconUrl]];
    _label.text = contest.contestDescription;
//    [_label sizeToFit];
//    _label.center = CGPointMake(80, CGRectGetMaxY(_img.frame)+45);
}

@end


@interface FFContest2UpTabelViewCell ()

@property (nonatomic) NSMutableDictionary *views;

@end


@implementation FFContest2UpTabelViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _views = [NSMutableDictionary dictionaryWithCapacity:4];
    }
    return self;
}

- (FFContestBitView *)getViewForIndex:(NSUInteger)idx
{
    FFContestBitView *view;
    if (!_views[@(idx)]) {
        view = [[FFContestBitView alloc] initWithFrame:CGRectMake(idx*160, 0, 160, 145)];
        view.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
        _views[@(idx)] = view;
    } else {
        view = _views[@(idx)];
    }
    return view;
}

- (void)setContests:(NSArray *)contests
{
    _contests = contests;
    
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    for (int i = 0; i < contests.count; i++) {
        FFContestBitView *bit = [self getViewForIndex:i];
        bit.contest = contests[i];
        [self.contentView addSubview:bit];
        
        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetMaxX(bit.frame), 11, 1, 123)];
        sep.backgroundColor = [FFStyle tableViewSeparatorColor];
        [self.contentView addSubview:sep];
        
        sep = [[UIView alloc] initWithFrame:CGRectMake(10, CGRectGetMaxY(self.contentView.frame)-1, 300, 1)];
        sep.backgroundColor = [FFStyle tableViewSeparatorColor];
        sep.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
        [self.contentView addSubview:sep];
    }
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
