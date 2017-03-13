#Обёртка для работы с API сервиса ahunter.ru
package AhunterAPI;
{
  use strict;
  use utf8;
  use LWP::UserAgent;
  use JSON;
  use Encode;
  
  #Конструирует объект
  sub new( $$ )
  {
    my ( $class, $Token ) = @_;
    
    my $self = 
    { 
      user_agent => LWP::UserAgent->new( agent => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:51.0) Gecko/20100101 Firefox/51.0", timeout => 600, keep_alive => 10 )
    };

    bless( $self, $class );

    return $self;    
  }
  
  #Отсылает HTTP-запрос сервису для получения подсказок по заданному префиксу
  #Должен вернуть объектную обёртку поверх JSON-ответа
  sub RequestSuggestions( $$ )
  {
    my ( $self, $Prefix ) = @_;
    
    my $Response = $self->{ user_agent }->get( "http://ahunter.ru/site/suggest/address?output=json;input=utf8;query=$Prefix;" );
    
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
      if( $self->CompareTestWithSuggestion( $Test, $Value->{value}, $Stage ) == 1 )
      {
        $Result = $Value->{value};
        last;
      }
      $LimitTopN --;
      last if( $LimitTopN == 0 );
    }
    
    return $Result;
  }
  
  #Сравнивает полученную от сервиса подсказку с целевым значением
  sub CompareTestWithSuggestion( $$$ )
  {
    my ( $self, $Test, $Value, $Stage ) = @_;
    
    #Склеиваем целевой результат так, чтобы получить формат подсказки данного сервиса
    my $Target = $Test->{reg_type}." ".$self->TransformRegionName( $Test->{reg} ).", ";
    
    #Город может не присутствовать в тесте, если имеем дело с городом фед. значения
    if( $Test->{city} ne "" )
    {
      $Target .= $Test->{city_type}." ".$Test->{city}.", ";
    }
    
    if( $Stage eq "street" )
    {
      $Target .= $Test->{street_type}." ".$Test->{street}.", ";
    }
    
    my $RetVal = ( $Target eq $Value ? 1 : 0 );
    
    return $RetVal;
  }
  
  #Преобразует имена некторых регионов для корректного сравнения
  sub TransformRegionName( $$ )
  {
    my ( $self, $RegName ) = @_;
    
    if( $RegName eq "Чувашская" )
    {
      $RegName = "Чувашская (Чувашия)";
    }
    
    return $RegName;
  }
};
1;