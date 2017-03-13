#Обёртка для работы с API сервиса dadata.ru
package DadataAPI;
{
  use strict;
  use warnings;
  use utf8;
  use LWP::UserAgent;
  use HTTP::Request;
  use JSON;
  use Encode;
  
  #Конструирует объект
  sub new( $$ )
  {
    my ( $class, $Token ) = @_;
    
    my $self = 
    { 
      user_agent => LWP::UserAgent->new( agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:51.0) Gecko/20100101 Firefox/51.0", timeout => 600, keep_alive => 10 ),
      
      token => $Token
    };

    bless( $self, $class );

    return $self;    
  }
  
  #Отсылает HTTP-запрос сервису для получения подсказок по заданному префиксу
  #Должен вернуть объектную обёртку поверх JSON-ответа
  sub RequestSuggestions( $$ )
  {
    my ( $self, $Prefix ) = @_;
    
    my %JSONRequest = ( query => $Prefix, count => 10 );
    my $JSONText = to_json( \%JSONRequest );
    
    my $Request = HTTP::Request->new( 'POST', "http://dadata.ru/api/v2/suggest/address" );
    $Request->header( 'Content-Type' => 'application/json' );
    $Request->header( 'Accept' => 'application/json' );
    $Request->header( 'Authorization' => "Token $self->{token}" );
    $Request->header( 'Origin' => 'http://dadata.ru' );
    $Request->header( 'Referer' => 'http://dadata.ru/suggestions/' );
    $Request->content( Encode::encode( "utf8", $JSONText ) );

    my $Response = $self->{ user_agent }->request( $Request );
    
    my $Result = undef;
    
    if( defined($Response) && $Response->is_success() )
    {
      $Result = from_json( Encode::decode( "utf8", $Response->content ) );
      
      #Если сервис не вернул подсказки, возвращаем undef
      if( defined( $Result ) && !exists( $Result->{suggestions} ) )
      {
        $Result = undef;
      }
    }
    
    return $Result;
  }
  
  #Ищет среди возвращённых сервисом подсказок целевую
  sub FindPrediction( $$$$$ )
  {
    my ( $self, $Test, $Suggestions, $Stage, $LimitTopN ) = @_;
    
    my $Result = "";
    
    foreach my $Value ( @{ $Suggestions->{suggestions} } )
    {
      #Сравниваем подсказку с целевым результатом, если совпала, значит сервис сделал правильное предсказание
      #КЛАДР есть не у всех адресов, возвращаемых данным сервисом, поэтому отдельно
      #проверяем его наличие
      if( defined( $Value->{data}->{kladr_id} ) && $self->CompareTestWithSuggestion( $Test, $Value->{data}->{kladr_id}, $Stage ) == 1 )
      {
        $Result = $Value->{unrestricted_value};
        last;
      }
      $LimitTopN --;
      last if( $LimitTopN == 0 );
    }
    
    return $Result;
  }
  
  #Сравнивает полученную от сервиса подсказку с целевым значением
  #Данный сервис возвращает коды КЛАДР, поэтому реально сравниваем целевой код с полученным
  sub CompareTestWithSuggestion( $$$ )
  {
    my ( $self, $Test, $KLADR_ID, $Stage ) = @_;
    
    my $RetVal = 0;
    
    if( $Stage eq "city" )
    {
      if( $Test->{city_kladr} ne "" )
      {
        #Если код КЛАДР содержит информацию о доме, отрезаем её
        $KLADR_ID = substr( $KLADR_ID, 0, length( $Test->{city_kladr} ) ) if( length( $KLADR_ID  ) > length( $Test->{city_kladr} ) );
        
        $RetVal = ( $Test->{city_kladr} eq $KLADR_ID ? 1 : 0 );
      }
      else
      {
        #Если код КЛАДР содержит информацию о доме, отрезаем её
        $KLADR_ID = substr( $KLADR_ID, 0, length( $Test->{reg_kladr} ) ) if( length( $KLADR_ID  ) > length( $Test->{reg_kladr} ) );
        
        $RetVal = ( $Test->{reg_kladr} eq $KLADR_ID ? 1 : 0 );
      }
    }
    elsif( $Stage eq "street" )
    {
      #Если код КЛАДР содержит информацию о доме, отрезаем её
      if( length( $KLADR_ID  ) > length( $Test->{street_kladr} ) )
      {
        $KLADR_ID = substr( $KLADR_ID, 0, length( $Test->{street_kladr} ) );
      }
      
      $RetVal = ( $Test->{street_kladr} eq $KLADR_ID ? 1 : 0 );
    }
    
    return $RetVal;
  }
};
1;