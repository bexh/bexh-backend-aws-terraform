output "outgoing_bets" {
    value = aws_kinesis_stream.outgoing_bets
}

output "incoming_bets" {
    value = aws_kinesis_stream.incoming_bets
}

output "outgoing_events" {
    value = aws_kinesis_stream.outgoing_events
}