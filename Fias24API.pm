#Обёртка для работы с API сервиса fias24.ru
package Fias24API;
{
  use strict;
  use warnings;
  use utf8;
  use LWP::UserAgent;
  use HTTP::Request;
  use HTTP::Request::Common;
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
    
    my $Request = POST( "https://fias24.ru/find.php",
                        'Content-Type' => 'application/x-www-form-urlencoded',
                        'Accept' => '*/*',
                        'Origin' => 'https://fias24.ru',
                        'Host' => 'fias24.ru',
                        'Referer' => 'https://fias24.ru/index.php',
                        Content => [ "text" => $Prefix, "format" => "json", "token" => $self->{token}, "region" => "", "count" => 10 ] );

    my $Response = $self->{ user_agent }->request( $Request );
    
    my $Result = undef;
    
    if( defined($Response) && $Response->is_success() )
    {
      $Result = from_json( Encode::decode( "utf8", $Response->content ) );
    }
    
    return $Result;
  }
  
  #Ищет среди возвращённых сервисом подсказок целевую
  sub FindPrediction( $$$$$ )
  {
    my ( $self, $Test, $Suggestions, $Stage, $LimitTopN ) = @_;
    
    my $Result = "";
    
    foreach my $Value ( @$Suggestions )
    {
      #Сравниваем подсказку с целевым результатом, если совпала, значит сервис сделал правильное предсказание
      if( $self->CompareTestWithSuggestion( $Test, $Value->{address}, $Stage ) == 1 )
      {
        $Result = $Value->{address};
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
    my $Target = $self->TransformRegionName( $Test->{reg}, $Test->{reg_type} );
    
    #Город может не присутствовать в тесте, если имеем дело с городом фед. значения
    if( $Test->{city} ne "" )
    {
      $Target .= ", ".$Test->{city_type}." ".$Test->{city};
    }
    
    if( $Stage eq "street" )
    {
      $Target .= ", ".$Test->{street_type}." ".$Test->{street};
    }
    
    my $RetVal = ( $Target eq $Value ? 1 : 0 );
    
    return $RetVal;
  }
  
  #Преобразует имена некторых регионов из тестов в имена, принятые в данном сервисе
  sub TransformRegionName( $$$ )
  {
    my ( $self, $RegName, $RegType ) = @_;
    
    my $Result = "";
    
    if( $RegName eq "Чувашская" )
    {
      $Result = "Чувашия Чувашская Республика -";
    }
    else
    {
      $Result = $RegType." ".$RegName;
    }
    
    return $Result;
  }
};
1;